--------------------------------------------------------------------------------
-- Routes: the fastest way to a marker. Riding and swimming over the terrain (a network built
-- from the game's map files: RouteNet.lua), the flight paths you know, Forever's boats,
-- zeppelins, tram, skycutter and portal, the lifts, gates, bridges and tunnels between zones,
-- and your hearthstone: a shortest path over them all (Dijkstra), shown as steps on the map
-- with the way drawn, an arrow to each step in turn, moving on as you arrive. Which flight
-- paths a character knows is learned at flight masters; how long flights take and how fast you
-- ride, as you go.
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local Route = {}
ns.Route = Route

local route   -- the route being followed: { steps, at, total, dest }
local preview -- a farming loop looked at, not yet ridden: { { ui, x, y }, ... } (drawn while no route is)

local HBD = ns.MapLib and ns.MapLib("HBD", "GetWorldCoordinatesFromZone") or (LibStub and LibStub("HereBeDragons-2.0", true))
local sqrt, max, min, floor = math.sqrt, math.max, math.min, math.floor

local RUN = 7                  -- yards a second, on foot
local MOUNT_60 = 11.2          -- (a 60% mount: from level 40, until a faster one is seen)
local GROUND_DETOUR = 1.25     -- a ride is this much longer than the straight line (hills, roads)
local FLIGHT_SPEED = 30        -- yards a second on a flight, until it's been flown and timed
local FLIGHT_DETOUR = 1.4      -- (flight paths go round too)
local FLIGHT_EXTRA = 30        -- seconds to talk to the flight master, take off and land
local CHANGE_PENALTY = 20      -- seconds a flight, transport or hearth counts extra in choosing
                               -- (not in the times shown): near enough, the way with fewer steps
local HEARTHSTONE = 6948
local HEARTH_COST = 25         -- seconds: the cast and the loading screen
local SHORT_HOP = 25           -- yards: a ride shorter than this isn't a step of its own
local TICK = 0.5               -- seconds between checks of where you are
-- seconds a transport takes, the average wait for it included
local TRANSPORT_COST = { boat = 240, zeppelin = 220, tram = 90, portal = 15, skycutter = 200, lift = 30 }
-- yards from a step's end that count as there
local ARRIVE = { ride = 30, fly = 120, transport = 150, hearth = 400, exit = 60, pickup = 15, swim = 40, farm = 60 }
-- a flight path you don't have is picked up on the way when going by it adds less riding than
-- this (yards), or than this share of that ride, whichever is more
local PICKUP_DETOUR, PICKUP_SHARE = 900, 0.4
local FM_AT_HAND = 600   -- yards: a flight master you don't have, this near you, is one to fly from
-- a zone more than this many levels above you is dangerous to ride through: it counts this
-- much more for each level over, up to the most (a flight, a boat: no danger)
local DANGER_FROM, DANGER_PER, DANGER_MAX, WARN_FROM = 2, 0.6, 8, 5
-- the levels of the zones, when the game doesn't say (its own, C_Map.GetMapLevels, first)
local ZONE_LEVELS = {
	[1429] = 1, [1426] = 1, [1438] = 1, [1411] = 1, [1412] = 1, [1420] = 1, [1436] = 10, [1432] = 10, [1439] = 10,
	[1413] = 10, [1421] = 10, [1433] = 15, [1442] = 15, [1440] = 18, [1431] = 18, [1437] = 20, [1424] = 20,
	[1441] = 25, [1416] = 30, [1417] = 30, [1445] = 35, [1418] = 35, [1443] = 30, [1434] = 30, [1435] = 35,
	[1444] = 40, [1446] = 40, [1427] = 43, [1425] = 40, [1449] = 48, [1448] = 48, [1428] = 50,
	[1419] = 45, [1447] = 45, [1422] = 51, [1452] = 55, [1423] = 53, [1451] = 55, [1430] = 55, [1450] = 1,
	-- (WoW Forever's own zones: by the levels of the mobs QuestieDB has in each, set as the
	-- others' above sit against theirs: Mount Hyjal, the Riverglades, Shen'dralas, Zephras Isle)
	[2482] = 53, [2548] = 33, [2652] = 38, [2521] = 1, [2665] = 1,
}
local zoneMin = {}
local function ZoneMin(ui)
	if zoneMin[ui] ~= nil then return zoneMin[ui] or nil end
	local lo
	if C_Map.GetMapLevels then
		local ok, a = pcall(C_Map.GetMapLevels, ui)
		if ok and type(a) == "number" and a > 0 then lo = a end
	end
	lo = lo or ZONE_LEVELS[ui]
	zoneMin[ui] = lo or false
	return lo
end
local function ZoneMax(ui)
	if C_Map.GetMapLevels then
		local ok, _, b = pcall(C_Map.GetMapLevels, ui)
		if ok and type(b) == "number" and b > 0 then return b end
	end
end
-- how much more riding through a zone counts, for your level (1: no more)
local function Danger(ui)
	local lo = ui and ZoneMin(ui)
	if not lo then return 1 end
	local over = lo - (UnitLevel("player") or 1)
	if over <= DANGER_FROM then return 1 end
	return math.min(DANGER_MAX, 1 + (over - DANGER_FROM) * DANGER_PER)
end
Route.Danger = Danger
Route.ZoneMin = ZoneMin

--------------------------------------------------------------------------------
-- Forever's transports, each way it goes: from (map, x, y) to (map, x, y), what it is, and
-- whose ("A", "H"; nil for anyone's). Docks and towers as the game's maps place them.
--------------------------------------------------------------------------------

-- Ways over the ground the network hasn't a link for (a flight of stairs its squares are too
-- coarse for, a pass it goes the long way round to): { map, x, y, map, x, y (0..100, its two
-- ends), seconds to ride it }. Ridden either way
local WAY_HOP = 150   -- yards: an end of a way this near where you are, or a dock, is stepped straight onto
local WAYS = {
	{ 1434, 48.0, 17.5, 1434, 53.9, 17.6, 40 },   -- Stranglethorn: from by Lake Nazferiti up the stairs to Zul'Gurub's gate
	{ 1411, 51.9, 41.3, 1411, 52.2, 35.5, 24 },   -- Durotar: Razor Hill out by its north road
	{ 1411, 52.2, 35.5, 1411, 45.6, 12.1, 87 },   -- and up the road to Orgrimmar's gate (the terrain's counts)
	{ 1411, 52.2, 35.5, 1411, 50.8, 13.8, 78 },   -- or to the zeppelin towers outside it
	{ 1434, 31.6, 29.0, 1434, 48.0, 17.5, 112 },  -- Grom'gol Base Camp straight north-east to the lake (the terrain's count)
	-- (the pass from Mulgore into Desolace, west of Thunder Bluff: from its mouth in Mulgore, at
	-- 31.8, 22.6, through to Desolace's road. It used to start by Thunder Bluff's foot, right
	-- under the lifts, and a route west would take the lift up and step onto it from the top)
	{ 1412, 31.8, 22.6, 1443, 74.5, 29.5, 50 },
}

-- (the ninth number is the leg's seconds: half the ship's round trip, the wait on average, and
-- the ride, from the game's own schedules (client 1.60.1); a leg without one counts its kind's)
local LEGS = {
	-- zeppelins: Orgrimmar and Undercity (the Thundercaller), Orgrimmar and Grom'gol (the Iron
	-- Eagle), Undercity and Grom'gol (the Purple Princess); the skycutter from Skywatch Plateau
	-- in Mulgore to Zephras Isle's Windshapers Dock
	{ 1411, 51.0, 13.9, 1420, 60.6, 58.9, "zeppelin", "H", 309 },
	{ 1420, 60.6, 58.9, 1411, 51.0, 13.9, "zeppelin", "H", 283 },
	{ 1411, 50.5, 12.7, 1434, 31.2, 30.4, "zeppelin", "H", 230 },
	{ 1434, 31.2, 30.4, 1411, 50.5, 12.7, "zeppelin", "H", 257 },
	{ 1420, 61.9, 58.9, 1434, 31.5, 29.1, "zeppelin", "H", 264 },
	{ 1434, 31.5, 29.1, 1420, 61.9, 58.9, "zeppelin", "H", 287 },
	{ 1412, 34.3, 26.1, 2521, 57.7, 81.0, "skycutter", "H", 277 },
	{ 2521, 57.7, 81.0, 1412, 34.3, 26.1, "skycutter", "H", 327 },
	-- the goblins' boats: Ratchet and Booty Bay (the Maiden's Fancy); Steamwheedle Port and
	-- Powderfuse Port in the Riverglades
	{ 1413, 63.8, 38.8, 1434, 25.7, 73.1, "boat", nil, 283 },
	{ 1434, 25.7, 73.1, 1413, 63.8, 38.8, "boat", nil, 300 },
	{ 1446, 68.6, 23.0, 2548, 80.6, 54.6, "boat", nil, 212 },
	{ 2548, 80.6, 54.6, 1446, 68.6, 23.0, "boat", nil, 211 },
	-- Dalaran's skycutter to Zephras Isle's High Order Dock
	{ 1416, 12.8, 51.2, 2521, 65.8, 83.8, "skycutter", nil, 288 },
	{ 2521, 65.8, 83.8, 1416, 12.8, 51.2, "skycutter", nil, 311 },
	-- the Alliance's boats: Menethil and Theramore (the Lady Mehley); Menethil, Southshore and
	-- Auberdine (the Bravery, round the three; staying aboard past a stop is a leg of its own);
	-- Rut'theran and Auberdine (the Moonspray); Auberdine's own pier and Stormwind Harbor
	{ 1437, 5.0, 63.5, 1445, 71.6, 56.4, "boat", "A", 269 },
	{ 1445, 71.6, 56.4, 1437, 5.0, 63.5, "boat", "A", 271 },
	{ 1437, 4.6, 57.1, 1424, 50.7, 70.4, "boat", "A", 385 },
	{ 1424, 50.7, 70.4, 1439, 32.4, 43.8, "boat", "A", 328 },
	{ 1439, 32.4, 43.8, 1437, 4.6, 57.1, "boat", "A", 322 },
	{ 1437, 4.6, 57.1, 1439, 32.4, 43.8, "boat", "A", 530 },
	{ 1424, 50.7, 70.4, 1437, 4.6, 57.1, "boat", "A", 467 },
	{ 1439, 32.4, 43.8, 1424, 50.7, 70.4, "boat", "A", 524 },
	{ 1439, 33.2, 40.2, 1438, 54.8, 97.2, "boat", "A", 250 },
	{ 1438, 54.8, 97.2, 1439, 33.2, 40.2, "boat", "A", 262 },
	{ 1439, 30.5, 40.9, 1453, 22.0, 57.0, "boat", "A", 191 },
	{ 1453, 22.0, 57.0, 1439, 30.5, 40.9, "boat", "A", 183 },
	-- Feathermoon's ferry, the Deeprun Tram, and Stormwind's portal to Dalaran
	{ 1444, 43.3, 42.8, 1444, 31.0, 39.7, "boat", "A", 296 },
	{ 1444, 31.0, 39.7, 1444, 43.3, 42.8, "boat", "A", 219 },
	{ 1453, 69.4, 30.5, 1455, 76.6, 51.2, "tram", "A", 130 },
	{ 1455, 76.6, 51.2, 1453, 69.4, 30.5, "tram", "A", 130 },
	{ 1453, 50.0, 87.0, 1416, 12.5, 51.8, "portal", "A" },
	-- Rut'theran Village, at the foot of Teldrassil, and Darnassus on top of it: the portal (no
	-- way up the trunk)
	{ 1438, 55.9, 89.8, 1457, 30.0, 41.4, "portal" },
	{ 1457, 30.0, 41.4, 1438, 55.9, 89.8, "portal" },
	-- a lift inside one zone, its foot and its top (each a little off the edge, on its own
	-- ground): Freewind Post's, up its mesa in Thousand Needles
	{ 1441, 43.1, 46.6, 1441, 44.8, 49.5, "lift" },
	{ 1441, 44.8, 49.5, 1441, 43.1, 46.6, "lift" },
}
Route.LEGS = LEGS

--------------------------------------------------------------------------------
-- Where one zone (or city) meets the next, by road or pass: { zone, x, y (on its map), the
-- other zone, what it is ("lift", "bridge", "tunnel", "gate"; a road when none), and, if not
-- the usual, how far (yards) its mouth reaches its own zone's ways }. Riding stays
-- in a zone; it changes zone at one of these. A zone with none listed (Forever's new ones) is
-- ridden across straight only from or to a place in it
--------------------------------------------------------------------------------

local EXITS = {
	-- the Eastern Kingdoms: the cities
	{ 1429, 32.0, 49.5, 1453 , "gate" },   -- Elwynn Forest, Stormwind City
	{ 1426, 53.5, 34.5, 1455 , "gate" },   -- Dun Morogh, Ironforge
	{ 1420, 61.9, 65.0, 1458 , "lift" },   -- Tirisfal Glades, Undercity
	-- Elwynn and the south
	{ 1429, 20.6, 80.6, 1436 , "bridge" },   -- Elwynn, Westfall
	{ 1429, 41.5, 93.5, 1431 },   -- Elwynn, Duskwood
	{ 1429, 95.0, 72.3, 1433 },   -- Elwynn, Redridge Mountains
	{ 1436, 68.0, 70.5, 1431 },   -- Westfall, Duskwood
	{ 1431, 86.5, 9.0, 1433 },    -- Duskwood, Redridge (Three Corners)
	{ 1431, 90.5, 41.0, 1430 },   -- Duskwood, Deadwind Pass
	{ 1431, 44.5, 88.5, 1434 },   -- Duskwood, Stranglethorn Vale
	{ 1430, 60.2, 43.1, 1435 },   -- Deadwind Pass, Swamp of Sorrows
	{ 1435, 34.5, 66.0, 1419 },   -- Swamp of Sorrows, Blasted Lands
	-- (Redridge to Burning Steppes, and to Swamp of Sorrows: in Forever the Riverglades lies between)
	-- Khaz Modan
	{ 1426, 85.5, 51.2, 1432 , "tunnel" },   -- Dun Morogh, Loch Modan
	{ 1432, 46.2, 76.0, 1418 },   -- Loch Modan, Badlands
	{ 1432, 20.5, 10.5, 1437 , "tunnel" },   -- Loch Modan, Wetlands (Dun Algaz)
	-- the north
	{ 1437, 51.0, 10.5, 1417 , "bridge" },   -- Wetlands, Arathi Highlands (Thandol Span)
	{ 1417, 20.3, 30.0, 1424 },   -- Arathi Highlands, Hillsbrad Foothills
	{ 1424, 12.5, 46.5, 1421 },   -- Hillsbrad, Silverpine Forest
	{ 1424, 55.8, 19.5, 1416 },   -- Hillsbrad, Alterac Mountains
	{ 1424, 63.5, 1.0, 1416 },    -- Hillsbrad, Alterac (north out of Tarren Mill)
	{ 1424, 88.0, 33.0, 1425 },   -- Hillsbrad, the Hinterlands
	{ 1421, 67.5, 4.6, 1420 },    -- Silverpine, Tirisfal Glades
	{ 1420, 83.5, 69.8, 1422 },   -- Tirisfal, Western Plaguelands
	{ 1416, 80.0, 33.0, 1422 },   -- Alterac Mountains, Western Plaguelands
	{ 1422, 69.5, 50.2, 1423 },   -- Western, Eastern Plaguelands
	-- Kalimdor: the cities
	{ 1411, 45.6, 12.1, 1454 , "gate" },   -- Durotar, Orgrimmar
	{ 1412, 40.7, 31.7, 1456 , "lift" },   -- Mulgore, Thunder Bluff (the lifts on its north side)
	{ 1438, 29.5, 56.0, 1457 , "gate" },   -- Teldrassil, Darnassus
	-- the Barrens and around
	{ 1411, 34.7, 42.6, 1413 , "bridge" },   -- Durotar, the Barrens
	{ 1412, 70.5, 56.5, 1413 },   -- Mulgore, the Barrens
	{ 1412, 31.8, 22.6, 1443 },   -- Mulgore, Desolace (the pass west of Thunder Bluff: Mulgore's one way west)
	{ 1412, 40.0, 13.3, 1442 },   -- Mulgore, Stonetalon Mountains
	{ 1413, 48.3, 5.7, 1440 , "gate" },    -- the Barrens, Ashenvale (Mor'shan)
	{ 1413, 35.5, 27.6, 1442 },   -- the Barrens, Stonetalon Mountains
	{ 1413, 50.0, 78.6, 1445 },   -- the Barrens, Dustwallow Marsh
	{ 1413, 44.6, 90.5, 1441 , "lift" },   -- the Barrens, Thousand Needles
	-- the north
	{ 1440, 26.5, 4.0, 1439 },    -- Ashenvale, Darkshore
	{ 1440, 42.0, 71.0, 1442, "tunnel" },   -- Ashenvale, Stonetalon (the Talondeep Path)
	{ 1440, 56.0, 26.0, 1448 },   -- Ashenvale, Felwood
	{ 1440, 94.5, 47.5, 1447 },   -- Ashenvale, Azshara
	{ 1448, 64.5, 8.0, 1452 , "tunnel" },    -- Felwood, Winterspring (Timbermaw Hold)
	{ 1448, 63.0, 6.5, 1450 , "tunnel" },    -- Felwood, Moonglade
	-- the west and south
	{ 1442, 29.5, 77.5, 1443 },   -- Stonetalon, Desolace
	{ 1443, 45.0, 95.0, 1444 },   -- Desolace, Feralas
	{ 1444, 89.0, 46.0, 1441 },   -- Feralas, Thousand Needles
	{ 1441, 76.5, 97.0, 1446 },   -- Thousand Needles, Tanaris
	{ 1446, 31.7, 28.5, 1449 },   -- Tanaris, Un'Goro Crater
	{ 1449, 29.0, 22.5, 1451, "ramp" },   -- Un'Goro, Silithus (the ramp out of the crater)
	{ 1427, 35.0, 84.0, 1428, "tunnel", 700 },   -- Searing Gorge, Burning Steppes (Blackrock Mountain:
	-- its walls shut the gorge in, so the way out is down off the gorge's floor, a little further)
}
Route.EXITS = EXITS

-- riding distance over the straight line, where a place joins the network: a city's streets wind
local CITY_WINDING = { [1453] = 1.5, [1455] = 1.9, [1458] = 1.9, [1454] = 1.5, [1456] = 1.5, [1457] = 1.5 }
local function PathFactor(ui)
	return (ui and CITY_WINDING[ui]) or 1.15
end

--------------------------------------------------------------------------------
-- What's kept: per character, the flight paths known (by continent, once a flight master's
-- been seen there) and the fastest mount seen; for everyone, how long each flight took
--------------------------------------------------------------------------------

local function Me() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end

local function Store()
	local db = ns.db
	if not db then return end
	db.route = db.route or {}
	local r = db.route
	r.known = r.known or {}       -- (as it was kept: by continent map)
	r.learned = r.learned or {}   -- [character] = { [world: 0, 1 ...] = { [flight path name] = true } }
	r.speed = r.speed or {}       -- [character] = yards a second, the fastest mounted seen
	r.flights = r.flights or {}   -- ["from|to"] = seconds
	return r
end

--- yards a second you ride at (your mount's, once seen; a guess by your level until then)
local function GroundSpeed()
	local r = Store()
	local seen = r and r.speed[Me()]
	if seen and seen > RUN then return seen end
	return (UnitLevel("player") or 1) >= 40 and MOUNT_60 or RUN
end
Route.GroundSpeed = GroundSpeed

--------------------------------------------------------------------------------
-- Places in the world: yards (as HereBeDragons has them) and the instance they're in
--------------------------------------------------------------------------------

local function World(ui, x, y)   -- x, y 0..1
	if not (HBD and HBD.GetWorldCoordinatesFromZone) then return end
	return HBD:GetWorldCoordinatesFromZone(x, y, ui)
end

-- the zone a map is in (a city's, a cave's: up to the zone)
local function ZoneOf(ui)
	local id, guard = ui, 0
	while id and guard < 6 do
		local info = C_Map.GetMapInfo(id)
		if not info then return ui end
		if (info.mapType or 0) <= 3 then return id end   -- (3: a zone)
		id, guard = info.parentMapID, guard + 1
	end
	return ui
end

-- the nearest named place in a zone (Towns.lua) to a point (0..1): "Booty Bay", "Grom'gol Base Camp"
local townsByMap
local function PlaceName(ui, x, y)
	if not townsByMap then
		townsByMap = {}
		for name, m, tx, ty in (ns.TOWNS or ""):gmatch("([^\n|]+)|(%d+)|(%d+)|(%d+)") do
			m = tonumber(m)
			townsByMap[m] = townsByMap[m] or {}
			table.insert(townsByMap[m], { name, tonumber(tx) / 1000, tonumber(ty) / 1000 })
		end
	end
	local best, bd
	for _, t in ipairs(townsByMap[ui] or {}) do
		local d = (t[2] - x) ^ 2 + (t[3] - y) ^ 2
		if not bd or d < bd then best, bd = t[1], d end
	end
	-- (close enough to be that place: within a tenth of the map)
	if best and bd < 0.01 then return best end
	return ns.ZoneName(ui) or "?"
end

Route.PlaceName = PlaceName

--------------------------------------------------------------------------------
-- The flight paths: every one of your faction's (and the neutral ones), from the game's taxi
-- map data, with which you know
--------------------------------------------------------------------------------

local flightNodes   -- { { name, ui (zone), x, y (0..1 on it), wx, wy, inst, cont, faction, nodeID }, ... }

local function Continents()
	local out, seen = {}, {}
	local kids = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(947, Enum and Enum.UIMapType and Enum.UIMapType.Continent, false)
	for _, c in ipairs(kids or {}) do
		if not seen[c.mapID] then seen[c.mapID] = true out[#out + 1] = c.mapID end
	end
	for _, id in ipairs({ 1414, 1415 }) do
		if not seen[id] then seen[id] = true out[#out + 1] = id end
	end
	return out
end

local function FlightNodes()
	if flightNodes then return flightNodes end
	flightNodes = {}
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return flightNodes end
	local seen = {}
	for _, cont in ipairs(Continents()) do
		local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, cont)
		for _, n in ipairs(ok and nodes or {}) do
			local id = n.nodeID or n.name
			local pos = n.position
			local x, y
			if pos then
				if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
			end
			-- (Blizzard's retired ones, still in the client's list: "zzOLDPowderfuse Port", "[DNT] ...")
			local retired = n.name and (n.name:find("^zz") or n.name:find("[DNT]", 1, true))
			if id and not seen[id] and x and y and n.name and not retired then
				seen[id] = true
				local wx, wy, inst = World(cont, x, y)
				local at = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(cont, x, y)
				local ui = at and ZoneOf(at.mapID) or cont
				local zx, zy
				if wx and HBD.GetZoneCoordinatesFromWorld then zx, zy = HBD:GetZoneCoordinatesFromWorld(wx, wy, ui, true) end
				if wx and zx then
					flightNodes[#flightNodes + 1] = { name = n.name, ui = ui, x = zx, y = zy, wx = wx, wy = wy,
						inst = inst, cont = cont, faction = n.faction, nodeID = n.nodeID }
				end
			end
		end
	end
	return flightNodes
end

Route.FlightNodes = FlightNodes

-- a flight path of your faction's (or a neutral one)
local function OursFlight(n)
	local f = n.faction
	if type(f) ~= "number" or f == 0 then return true end   -- (Enum.FlightPathFaction: 0 neutral, 1 Horde, 2 Alliance)
	return (f == 1 and ns.faction == "Horde") or (f == 2 and ns.faction == "Alliance")
end

-- the flight paths you were seen to have at a flight master, on a continent (by its world:
-- HereBeDragons' instance, 0 the Eastern Kingdoms, 1 Kalimdor), or nil: none opened there yet.
-- (Kept by continent map before: 1415, 1414)
local OLD_KEY = { [0] = 1415, [1] = 1414 }
local function LearnedFor(inst)
	local r = Store()
	if not r then return end
	local mine = r.learned[Me()]
	if mine and mine[inst] then return mine[inst] end
	local old = r.known[Me()]
	return old and OLD_KEY[inst] and old[OLD_KEY[inst]]
end

-- what the game itself says of each flight path, found or not, where it says anything: it lists
-- them all with "undiscovered" on the ones you haven't. WoW Forever's lists every one as found,
-- learned or not; then it isn't saying, and nil. { [nodeID] = found }, read again every few
-- seconds
local function GameSays()
	local now = GetTime()
	if now - (Route.saysAt or -math.huge) < 5 then return Route.says or nil end
	Route.saysAt, Route.says = now, false
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
	local found, hidden = {}, 0
	for _, cont in ipairs(Continents()) do
		local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, cont)
		for _, n in ipairs(ok and type(nodes) == "table" and nodes or {}) do
			if type(n) == "table" and n.nodeID then
				if n.isUndiscovered == true then hidden = hidden + 1
				elseif n.isUndiscovered == false then found[n.nodeID] = true end
			end
		end
	end
	-- (none marked undiscovered: not a list of what you have)
	if hidden > 0 then Route.says = found end
	return Route.says or nil
end

-- known to you: as learned at a flight master on its continent (its map shows what you have);
-- before you've opened one there, as the game says, where it does. Else not: a flight path isn't
-- taken for yours on a guess. (It was guessed once from where you'd explored, and a city's taken
-- as known; a new character was sent flying between cities it had never seen)
local function Known(n)
	local set = LearnedFor(n.inst)
	if set then return set[n.name] == true end
	local says = GameSays()
	if says and n.nodeID then return says[n.nodeID] == true end
	return false
end

--- whether MapSeek knows which flight paths you have on a continent (by its world): you've
--- opened a flight master's map there, or the game says of itself
function Route.FlightsKnown(inst)
	return LearnedFor(inst) ~= nil or GameSays() ~= nil
end

-- seconds a flight takes: as timed, else from how far it is
local function FlightCost(a, b)
	local r = Store()
	local t = r and r.flights[a.name .. "|" .. b.name]
	if t then return t + 5 end
	local d = sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2)
	return d * FLIGHT_DETOUR / FLIGHT_SPEED + FLIGHT_EXTRA
end

-- what a crossing step says, by what it is
local CROSS_TEXT = { lift = L["Take the lift into %s"], bridge = L["Cross the bridge into %s"],
	tunnel = L["Go through the tunnel into %s"], gate = L["Go through the gate into %s"], ramp = L["Go up the ramp into %s"] }

-- what a transport step says, by what it is
local GO_TO = { boat = L["Go to the boat to %s"], zeppelin = L["Go to the zeppelin to %s"], tram = L["Go to the tram to %s"],
	portal = L["Go to the portal to %s"], skycutter = L["Go to the skycutter to %s"],
	swim = L["Go to the shore, to swim to %s"], lift = L["Go to the lift to %s"] }
local TAKE = { boat = L["Take the boat to %s"], zeppelin = L["Take the zeppelin to %s"], tram = L["Take the tram to %s"],
	portal = L["Take the portal to %s"], skycutter = L["Take the skycutter to %s"], swim = L["Swim to %s"],
	lift = L["Take the lift to %s"] }

-- where your hearthstone takes you (its inn's town, or the innkeeper there), when it's ready
local function HearthSpot()
	local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(HEARTHSTONE)) or (GetItemCount and GetItemCount(HEARTHSTONE)) or 0
	if count < 1 then return end
	local cd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	if cd then
		local start, duration = cd(HEARTHSTONE)
		if start and start > 0 and duration and start + duration - GetTime() > 30 then return end
	end
	local bind = GetBindLocation and GetBindLocation()
	if not bind or bind == "" then return end
	local p = ns.Search and ns.Search.Place(bind)
	local pt = p and p.points and p.points[1]
	if not pt then return end
	return { ui = pt.ui, x = pt.x, y = pt.y, name = bind }
end

--------------------------------------------------------------------------------
-- The travel network (RouteNet.lua): the terrain of each continent as nodes about 500 yards
-- apart, joined by the quickest way over the ground between them (riding, or swimming where
-- it's water), built from the game's own map files. Read into tables the first time a route's
-- planned on a continent
--------------------------------------------------------------------------------

local NET_SWIM = 4.7           -- yards a second, swimming (as the network was timed)
local NET_RIDE = 11.2          -- yards a second riding (as the network was timed: a 60% mount)
local BUCKET = 500             -- yards: the nodes are found by the square they're in
local LINK_R = 600             -- yards: a place off the network (you, a flight master, a dock) joins the
local LINK_K = 3               --   nearest few nodes within this, in its own zone
local STRAIGHT_OK = 1.3        -- a route that's one ride, this near a straight line: no route to show ...
local SHORT_RIDE = 90          -- ... when it's this short (seconds). A longer ride's way is worth drawing, road and all
local TUNNEL_EXTRA = 10        -- seconds through a tunnel or up a ramp, past its length
local TUNNEL_R = 1400          -- yards: a tunnel's mouth joins the far zone's nodes within this (through the mountain)
local CITY = { [1453] = true, [1455] = true, [1458] = true, [1454] = true, [1456] = true, [1457] = true }
-- a city up its lift (Thunder Bluff on its mesas) or down it (Undercity): the ground its map
-- covers is the zone outside's, not the city's (the city's reached by the lift alone)
local LIFT_CITY = { [1456] = 1412, [1458] = 1420 }

local nets = {}
local NO_EDGES = {}   -- (the edges of a node that has none: one list for them all)

-- an edge's points between, as numbers (x, y, x, y ...), a to b as the network lists them
local function Mids(e)
	local m = {}
	for v in e.mids:gmatch("-?%d+") do m[#m + 1] = tonumber(v) end
	return m
end

-- whether two nodes are joined both ways: one piece of ground
local function TwoWay(net, a, b)
	local there, back = false, false
	for _, e in ipairs(net.adj[a]) do if e.to == b then there = true break end end
	if not there then return false end
	for _, e in ipairs(net.adj[b]) do if e.to == a then back = true break end end
	return back
end

-- Borders the terrain's heights make look open that the game doesn't let you over (a mountain
-- range it walls unseen): no way of the network crosses straight from one of the pair to the other
-- (A pair with a way between them listed, EXITS: the network's own ways by that one, both ends
-- within SHUT_GAP yards of it, stay: the road over the Bulwark. Its others go: down off the
-- hills north of it)
local SHUT = { { 1419, 1434 },   -- Blasted Lands - Stranglethorn Vale
	{ 1420, 1422 },                -- Tirisfal Glades - Western Plaguelands: only by the Bulwark
	-- Mulgore's rim: its ways out are to the Barrens, to Stonetalon, and to Desolace by the one
	-- pass west of Thunder Bluff (the ground's heights have its west and south rims leaking into
	-- Desolace, Shen'dralas and Feralas)
	{ 1412, 1443 }, { 1412, 2652 }, { 1412, 1444 } }
local SHUT_GAP = 900

-- The network's ways the ground model got wrong, put right by hand (each checked against the
-- game's own ground: tools/terrain/experimental/walkable.py, and a second model of it).
-- CUT: no edge between the nodes nearest these two points of a zone's map. LINKS: an edge both
-- ways between the nodes nearest the first and last points, by way of the ones between, costed
-- as a ride along them. A point names the node within Route.hand.r yards of it; a link's end
-- with none there gets a node of its own (Joins takes a place to one without asking the ground)
Route.hand = { r = 60, wind = 1.2 }   -- (r: yards a point names a node within; wind: a ramp's road over the straight runs)
Route.hand.cut = {
	-- Durotar: up from the Southfury's bank onto the Valley of Trials' rim and down into it. The
	-- valley's walled in (a starting valley), and the bake took its wall for a slope
	{ 1411, 37.6, 64.3, 39.3, 68.8 },
}
-- WALLS: a line of a zone's map nothing crosses: no straight line, no way of the ground, no edge
-- of the network (the game's own wall, where the ground's heights don't show it)
Route.hand.walls = {
	-- Durotar: the Valley of Trials' walls, all but its mouth to the east (a starting valley:
	-- in and out by that alone; the ground's heights have it leaking on every side)
	{ 1411, 49.5, 63.5, 47.5, 60.5, 40.5, 61.0, 39.5, 66.0, 40.0, 73.0, 46.0, 73.0, 48.7, 72.6 },
	-- Mulgore: the west rim just south of the Desolace pass, where the ground's heights have drops
	-- off Desolace's ridge into Mulgore (the pass is at 31.8, 22.6; nothing else crosses here)
	{ 1412, 29.5, 30.5, 29.5, 45.0 },
}
-- OPEN: a way of the network the bake has one way only (a slope it took for a drop) that the
-- game lets you ride both ways: the way back is given the same cost and points
Route.hand.open = {
	-- Moonglade: the road along Lake Elune'ara's west shore from the Timbermaw tunnel up to
	-- Nighthaven. The bake has it as a descent into the basin only, and Moonglade as a place with
	-- no way out
	{ 1450, 23.9, 60.1, 45.6, 60.1 },
	{ 1450, 23.9, 92.5, 45.6, 87.7 },
	-- Loch Modan: the roads up from the loch's shores to its north, Dun Algaz and the
	-- Stonewrought Dam, and the east shore's road south to Farstrider Lodge. The bake has them
	-- all as descents, and the loch's north and east as places with no way up to them
	{ 1432, 25.6, 33.3, 25.3, 6.6 },
	{ 1432, 41.6, 32.9, 25.3, 6.6 },
	{ 1432, 41.6, 32.9, 61.9, 6.1 },
	{ 1432, 80.0, 33.3, 80.0, 60.5 },
	-- Western Plaguelands: the road north from Andorhal up to Hearthglen (the bake has Hearthglen's
	-- rise as a descent only; routes went round through the Eastern Plaguelands)
	{ 1422, 49.2, 33.7, 49.2, 16.3 },
	-- Badlands: the road up onto Camp Kosh's rise from the south (a descent only in the bake, so
	-- Camp Kosh was reached round through Loch Modan)
	{ 1418, 65.2, 42.8, 65.2, 12.7 },
}
Route.hand.links = {
	-- Stonetalon: Sun Rock Retreat down its south-west road to the Charred Vale. The model has
	-- no way out of Sun Rock's bowl to the south at all; the road's a ramp
	{ 1442, { 47.5, 62.1 }, { 44.6, 72.2 }, { 34.4, 72.2 } },
	-- Azshara: the road west from Valormok to the Ashenvale border, over its bridge. The ground
	-- has a ravine there the bridge spans, and no bridge is in the ground's heights
	{ 1447, { 22.8, 67.3 }, { 12.8, 67.3 } },
	-- Moonglade: the road from Nighthaven's lake east and up to the pass into Winterspring (the
	-- bake has no way up out of the basin)
	{ 1450, { 67.2, 60.1 }, { 76.0, 74.0 }, { 84.0, 86.0 }, { 90.4, 94.2 } },
	-- Silverpine: Lordamere Lake's north shore, from the Dead Field east into Alterac at Dandred's
	-- Fold (the bake joins the shore to the Dead Field by drops from the hills only). Its ends get
	-- nodes of their own, and those are tied to the network's own (the north road's above the Dead
	-- Field, Alterac's by Dandred's Fold) by the two short links, so the shore's on the way
	-- through, not only from a place on it
	{ 1421, { 46.4, 21.7 }, { 51.2, 27.4 } },
	{ 1421, { 46.4, 21.7 }, { 63.0, 20.0 }, { 77.0, 18.5 }, { 90.0, 17.5 } },
	{ 1421, { 90.0, 17.5 }, { 86.5, 10.4 } },
	-- Silverpine: the Sepulcher up the road north to the network's node above the Dead Field. The
	-- town stands between the lattice's nodes, on a rise the bake has as pockets with one way down
	-- (south), so a route out of it wandered west and south before turning north: 170 seconds for
	-- a 46-second ride. The bake's own ground has this way both ways
	{ 1421, { 44.0, 40.0 }, { 44.4, 35.7 }, { 51.2, 27.4 } },
	-- Searing Gorge: the pass to Kargath, from the gorge's east down the canyon into the Badlands
	-- from the south-west. The bake has no way at all between the two zones (the canyon's sides
	-- are over its climb limit), so Thorium Point to Kargath went round through Blackrock
	-- Mountain and the Riverglades; the ground's heights at the game's limit do join them this way
	{ 1427, { 61.7, 33.6 }, { 66.5, 38.5 }, { 66.1, 50.0 }, { 73.4, 56.7 }, { 85.0, 52.2 }, { 84.4, 34.3 } },
	-- Eastern Plaguelands: from Crown Guard Tower north onto the road (the tower's node has only
	-- drops into the Hinterlands behind it)
	{ 1423, { 45.2, 79.9 }, { 45.2, 62.5 } },
	-- Feralas: up from the Forgotten Coast's lowland onto Dire Maul's plateau, round by the south.
	-- The bake has the step up as a drop only, and all of Feralas west of it with no way east but
	-- round through Shen'dralas and Mulgore (the Forgotten Coast to Camp Mojache was 15 minutes);
	-- the ground's heights at the game's limit join them this way
	{ 1444, { 48.6, 44.6 }, { 47.2, 44.8 }, { 48.5, 46.6 }, { 50.0, 51.5 }, { 53.3, 51.8 }, { 55.8, 48.1 }, { 55.8, 44.6 } },
	-- Mulgore: Skywatch Plateau, the skycutter's dock for Zephras Isle, tied to the nodes west and
	-- north of Thunder Bluff (the bake's own ways). The plateau is ground no node reaches in the
	-- bake, so the dock could be left but not come to on the way: there was no route from
	-- anywhere in Mulgore to the isle, unless you stood at the dock
	{ 1412, { 31.1, 29.2 }, { 34.2, 29.3 }, { 36.5, 24.4 }, { 34.3, 26.1 } },
	{ 1412, { 39.2, 17.1 }, { 37.0, 22.8 }, { 34.3, 26.1 } },
}

local shut = {}
for _, pair in ipairs(SHUT) do
	shut[pair[1]] = shut[pair[1]] or {}
	shut[pair[2]] = shut[pair[2]] or {}
	shut[pair[1]][pair[2]], shut[pair[2]][pair[1]] = true, true
end

-- the ways listed between two zones whose border's otherwise shut: where each is in the world
function Route.ShutGaps(za, zb)
	Route.gaps = Route.gaps or {}
	local key = za < zb and (za * 100000 + zb) or (zb * 100000 + za)
	local list = Route.gaps[key]
	if not list then
		list = {}
		for _, e in ipairs(Route.EXITS or {}) do
			if (e[1] == za and e[4] == zb) or (e[1] == zb and e[4] == za) then
				local wx, wy = World(e[1], e[2] / 100, e[3] / 100)
				if wx then list[#list + 1] = { wx, wy } end
			end
		end
		Route.gaps[key] = list
	end
	return list
end

-- whether the straight line from a to b crosses one of the hand's walls (none: never)
function Route.HandCross(net, ax, ay, bx, by)
	local walls = net and net.hwalls
	if not walls then return false end
	for _, w in ipairs(walls) do
		local cx, cy, dx, dy = w[1], w[2], w[3], w[4]
		local d = (bx - ax) * (dy - cy) - (by - ay) * (dx - cx)
		if d ~= 0 then
			local t = ((cx - ax) * (dy - cy) - (cy - ay) * (dx - cx)) / d
			local u = ((cx - ax) * (by - ay) - (cy - ay) * (bx - ax)) / d
			if t >= 0 and t <= 1 and u >= 0 and u <= 1 then return true end
		end
	end
	return false
end

local function Net(inst)
	if nets[inst] ~= nil then return nets[inst] or nil end
	local raw = ns.ROUTE_NET and ns.ROUTE_NET[inst]
	if not raw then nets[inst] = false return end
	local net = { x = {}, y = {}, zone = {}, swim = {}, grid = {} }
	local i = 0
	for hx, hy, z, s in raw.nodes:gmatch("(-?%d+),(-?%d+),(%d+),(%d)") do
		i = i + 1
		net.x[i], net.y[i], net.zone[i], net.swim[i] = tonumber(hx), tonumber(hy), tonumber(z), s == "1"
		net.zone[i] = LIFT_CITY[net.zone[i]] or net.zone[i]
		local key = floor(net.x[i] / BUCKET) * 100000 + floor(net.y[i] / BUCKET)
		local g = net.grid[key]
		if not g then g = {} net.grid[key] = g end
		g[#g + 1] = i
	end
	net.n = i
	-- the edges: not read into tables here (there are thousands, and a route needs the ones about
	-- it). Kept: where each starts in the one string, by the nodes it leaves; which nodes can be
	-- come to at all (a pocket's, a mesa's top or a walled yard, can only be left); and the
	-- drops. A node's edges are read, and kept, when a route first comes to it
	local all = raw.edges
	-- (the hand's cuts and links, by their nodes)
	local function NodeAt(ui, x, y)
		local wx, wy, winst = World(ui, x / 100, y / 100)
		if not wx or winst ~= inst then return end
		local best, bd = nil, Route.hand.r * Route.hand.r
		for k = 1, i do
			local d = (net.x[k] - wx) ^ 2 + (net.y[k] - wy) ^ 2
			if d < bd then best, bd = k, d end
		end
		return best
	end
	-- (the hand's walls, as lines in the world)
	net.hwalls = nil
	for _, w in ipairs(Route.hand.walls) do
		local last
		for k = 2, #w - 1, 2 do
			local wx, wy, winst = World(w[1], w[k] / 100, w[k + 1] / 100)
			if wx and winst == inst then
				if last then
					net.hwalls = net.hwalls or {}
					net.hwalls[#net.hwalls + 1] = { last[1], last[2], wx, wy }
				end
				last = { wx, wy }
			else
				last = nil
			end
		end
	end
	local cut = {}
	for _, c in ipairs(Route.hand.cut) do
		local a, b = NodeAt(c[1], c[2], c[3]), NodeAt(c[1], c[4], c[5])
		if a and b then
			cut[a] = cut[a] or {} cut[a][b] = true
			cut[b] = cut[b] or {} cut[b][a] = true
		end
	end
	local extra = {}
	local function NodeMade(ui, x, y)
		local n = NodeAt(ui, x, y)
		if n then return n end
		local wx, wy, winst = World(ui, x / 100, y / 100)
		if not wx or winst ~= inst then return end
		i = i + 1
		net.x[i], net.y[i], net.zone[i], net.swim[i] = wx, wy, LIFT_CITY[ui] or ui, false
		local key = floor(wx / BUCKET) * 100000 + floor(wy / BUCKET)
		local g = net.grid[key]
		if not g then g = {} net.grid[key] = g end
		g[#g + 1] = i
		net.hand = net.hand or {}
		net.hand[i] = true
		return i
	end
	for _, l in ipairs(Route.hand.links) do
		local a, b = NodeMade(l[1], l[2][1], l[2][2]), NodeMade(l[1], l[#l][1], l[#l][2])
		if a and b and a ~= b then
			local pts, yards, px, py = {}, 0, net.x[a], net.y[a]
			for k = 3, #l - 1 do
				local wx, wy = World(l[1], l[k][1] / 100, l[k][2] / 100)
				if wx then
					yards = yards + sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
					pts[#pts + 1] = ("%d,%d"):format(wx, wy)
					px, py = wx, wy
				end
			end
			yards = yards + sqrt((net.x[b] - px) ^ 2 + (net.y[b] - py) ^ 2)
			local secs = floor(yards * Route.hand.wind / NET_RIDE + 0.5)
			extra[#extra + 1] = ("%d,%d,%d,%d,0%s"):format(a, b, secs, secs, #pts > 0 and ("," .. table.concat(pts, ",")) or "")
		end
	end
	-- (opened by hand: the one-way ways between the named nodes, given their way back)
	local opened = {}
	for _, o in ipairs(Route.hand.open) do
		local a, b = NodeAt(o[1], o[2], o[3]), NodeAt(o[1], o[4], o[5])
		if a and b then opened[a .. "," .. b] = true opened[b .. "," .. a] = true end
	end
	if next(opened) then
		for seg in all:gmatch("[^;]+") do
			local a, b, cab, cba, rest = seg:match("^(%d+),(%d+),(%d+),(%d+)(.*)$")
			if a and opened[a .. "," .. b] then
				cab, cba = tonumber(cab), tonumber(cba)
				if (cab == 0) ~= (cba == 0) then
					local c = cab > 0 and cab or cba
					extra[#extra + 1] = ("%s,%s,%d,%d%s"):format(a, b, c, c, rest)
				end
			end
		end
	end
	if #extra > 0 then all = all .. (all ~= "" and ";" or "") .. table.concat(extra, ";") end
	net.n = i
	local drops = {}   -- (a free fall on the way that costs health, in yards, each way: by the edge's number)
	for n, dab, dba in (raw.drops or ""):gmatch("(%d+),(%d+),(%d+)") do
		drops[tonumber(n)] = { tonumber(dab), tonumber(dba) }
	end
	local of, dropAt = {}, {}
	net.inc = {}
	local pos, nEdge, len = 1, 0, #all
	while pos <= len do
		local stop = all:find(";", pos, true) or (len + 1)
		nEdge = nEdge + 1
		local a, b, cab, cba = all:match("^(%d+),(%d+),(%d+),(%d+)", pos)
		a, b, cab, cba = tonumber(a), tonumber(b), tonumber(cab) or 0, tonumber(cba) or 0
		-- (over a border that's shut: not an edge at all)
		local za, zb = a and net.zone[a], b and net.zone[b]
		if za and zb and shut[za] and shut[za][zb] then
			-- (but by a way between the two that's listed: both its ends near that)
			local open = false
			for _, g in ipairs(Route.ShutGaps(za, zb)) do
				if (net.x[a] - g[1]) ^ 2 + (net.y[a] - g[2]) ^ 2 <= SHUT_GAP * SHUT_GAP
					and (net.x[b] - g[1]) ^ 2 + (net.y[b] - g[2]) ^ 2 <= SHUT_GAP * SHUT_GAP then open = true break end
			end
			if not open then a = nil end
		end
		-- (over land that's of no zone: ground the map files have and the game doesn't let you
		-- onto, the empty country north of the Plaguelands, the far side of a range. Not a way.
		-- Water of no zone is the open sea off a coast, and is)
		if a and b and ((za == 0 and not net.swim[a]) or (zb == 0 and not net.swim[b])) then a = nil end
		-- (cut by hand, or over a wall set by hand, by the way it's drawn)
		if a and b and cut[a] and cut[a][b] then a = nil end
		if a and b and net.hwalls then
			local px, py = net.x[a], net.y[a]
			local mids = all:sub(pos, stop - 1):match("^%d+,%d+,%d+,%d+,%d+,?(.*)$") or ""
			local lx
			for v in mids:gmatch("-?%d+") do
				if lx then
					local qx, qy = lx, tonumber(v)
					if Route.HandCross(net, px, py, qx, qy) then a = nil break end
					px, py, lx = qx, qy, nil
				else
					lx = tonumber(v)
				end
			end
			if a and Route.HandCross(net, px, py, net.x[b], net.y[b]) then a = nil end
			if not a and Route.debugJoins then
				local oa, ob = all:match("^(%d+),(%d+)", pos)
				print(("CUT by wall: edge %s-%s"):format(oa, ob))
			end
		end
		if a and b and a <= i and b <= i then
			if cab > 0 then
				local t = of[a]
				if not t then t = {} of[a] = t end
				t[#t + 1] = pos
				net.inc[b] = true
			end
			if cba > 0 then
				local t = of[b]
				if not t then t = {} of[b] = t end
				t[#t + 1] = pos
				net.inc[a] = true
			end
			if drops[nEdge] then dropAt[pos] = drops[nEdge] end
		end
		pos = stop + 1
	end
	net.adj = setmetatable({}, { __index = function(t, u)
		local list = of[u]
		if not list then return NO_EDGES end
		local out = {}
		for _, at in ipairs(list) do
			local stop = all:find(";", at, true) or (len + 1)
			-- (the points between, to draw it by: kept as they're written, Mids)
			local a, b, cab, cba, swum, mids = all:sub(at, stop - 1):match("^(%d+),(%d+),(%d+),(%d+),(%d+),?(.*)$")
			a, b, cab, cba, swum = tonumber(a), tonumber(b), tonumber(cab) or 0, tonumber(cba) or 0, tonumber(swum)
			if mids == "" then mids = nil end
			swum = swum and swum > 0 and swum or nil
			local d = dropAt[at]
			if a == u and cab > 0 then
				out[#out + 1] = { to = b, cost = cab, swum = swum, mids = mids, fwd = true, drop = d and d[1] > 0 and d[1] or nil }
			end
			if b == u and cba > 0 then
				out[#out + 1] = { to = a, cost = cba, swum = swum, mids = mids, drop = d and d[2] > 0 and d[2] or nil }
			end
		end
		of[u] = nil
		rawset(t, u, out)
		return out
	end })
	-- (home: for each square of ground, the node that reaches it quickest; its rows read as asked for)
	if raw.home and raw.home.rows then
		-- (where each row starts in the one string: a row's cut out and read when it's first asked for)
		local starts, n, at = {}, 0, 1
		local all = raw.home.rows
		while true do
			n = n + 1
			starts[n] = at
			local bar = all:find("|", at, true)
			if not bar then break end
			at = bar + 1
		end
		starts[n + 1] = #all + 2
		net.home = { x = raw.home.x, y = raw.home.y, side = raw.home.side, rows = {}, n = n, all = all, starts = starts,
			wetAll = raw.home.wet }
		-- (walls: whether the ground lets you from each square to the next, east and south, and
		-- back. Rows as home's, read the same)
		if raw.home.walls then
			local ws, wn, wat = {}, 0, 1
			local wall = raw.home.walls
			while true do
				wn = wn + 1
				ws[wn] = wat
				local bar = wall:find("|", wat, true)
				if not bar then break end
				wat = bar + 1
			end
			ws[wn + 1] = #wall + 2
			net.walls = { rows = {}, n = wn, all = wall, starts = ws }
		end
	end
	nets[inst] = net
	return net
end

-- the node in one square of the home raster (row i, square j, from 1), or nil
local function HomeAt(h, i, j)
	if i < 1 or i > h.n or j < 1 then return end
	local row = h.rows[i]
	if not row then
		row = h.all:sub(h.starts[i], h.starts[i + 1] - 2)
		-- ("squares.node,squares,squares.node ..." in base 36: where each run ends, and its node)
		local ends, nodes, at = {}, {}, 0
		for len, node in row:gmatch("(%w+)%.?(%w*)") do
			at = at + tonumber(len, 36)
			ends[#ends + 1] = at
			nodes[#nodes + 1] = node ~= "" and tonumber(node, 36) or 0
		end
		row = { ends = ends, nodes = nodes }
		h.rows[i] = row
	end
	local ends = row.ends
	local lo, hi = 1, #ends
	if hi == 0 or j > ends[hi] then return end
	while lo < hi do
		local mid = floor((lo + hi) / 2)
		if ends[mid] >= j then hi = mid else lo = mid + 1 end
	end
	local node = row.nodes[lo]
	return node > 0 and node or nil
end

--- the node that reaches a point over the ground, and how far off it is: not the nearest as the
--- crow flies (that may be over a cliff, a wall or a gorge). A point no node reaches (in a
--- building, on a rock): the nearest square about it that one does. nil when the network has no
--- home raster, or nothing reaches anywhere near
local HOME_RINGS = 2   -- squares about the point looked in (25 yards each): a building's depth, not a cliff's
local function Home(net, wx, wy)
	local h = net.home
	if not h then return end
	local i = floor((h.x - wy) / h.side) + 1
	local j = floor((h.y - wx) / h.side) + 1
	local node = HomeAt(h, i, j)
	for ring = 1, HOME_RINGS do
		if node then break end
		local best
		for di = -ring, ring do
			for dj = -ring, ring do
				if max(math.abs(di), math.abs(dj)) == ring then
					local n = HomeAt(h, i + di, j + dj)
					local d = di * di + dj * dj
					if n and (not best or d < best) then best, node = d, n end
				end
			end
		end
	end
	if not node then return end
	return node, sqrt((net.x[node] - wx) ^ 2 + (net.y[node] - wy) ^ 2)
end


--------------------------------------------------------------------------------
-- The ground about a place, square by square (25 yards): which squares it lets you between
-- (the network's walls). A hill's side too steep, a cliff's face, a wall are squares shut; the
-- place it's climbed, a gap. So the way from where you are to the network, and from it to where
-- you're going, is the way that can be ridden: round to the hill's one side, not at its face
--------------------------------------------------------------------------------

local WALK_KEY = 8192      -- squares a row, for a square's one number
local WALK_STRAY = 16      -- yards a drawn way may stray from the squares' own
local WALK_FEW = 8         -- squares got to, or fewer: the place's own square is shut about
local WALK_RINGS = 2       -- squares about a place looked in for ground, when its own has none

-- whether the ground lets you from square (i, j) to the one a step (di, dj) from it: east, west,
-- south or north; or cornerwise, by either way round the corner
local function Open(net, i, j, di, dj)
	local w = net.walls
	if di ~= 0 and dj ~= 0 then
		return (Open(net, i, j, di, 0) and Open(net, i + di, j, 0, dj)) or (Open(net, i, j, 0, dj) and Open(net, i, j + dj, di, 0))
	end
	if net.hwalls then
		local h, side = net.home, net.home.side
		if Route.HandCross(net, h.y - (j - 0.5) * side, h.x - (i - 0.5) * side, h.y - (j + dj - 0.5) * side, h.x - (i + di - 0.5) * side) then return false end
	end
	if dj == 1 then return (HomeAt(w, i, j) or 0) % 2 >= 1 end
	if dj == -1 then return (HomeAt(w, i, j - 1) or 0) % 4 >= 2 end
	if di == 1 then return (HomeAt(w, i, j) or 0) % 8 >= 4 end
	return (HomeAt(w, i - 1, j) or 0) >= 8
end

-- the square a point's in; one with ground in it, the nearest about it when its own has none
local function SquareOf(net, wx, wy)
	local h, w = net.home, net.walls
	local i = floor((h.x - wy) / h.side) + 1
	local j = floor((h.y - wx) / h.side) + 1
	if HomeAt(w, i, j) then return i, j end
	local best, bi, bj
	for di = -WALK_RINGS, WALK_RINGS do
		for dj = -WALK_RINGS, WALK_RINGS do
			if HomeAt(w, i + di, j + dj) then
				local d = di * di + dj * dj
				if not best or d < best then best, bi, bj = d, i + di, j + dj end
			end
		end
	end
	return bi, bj
end

--- whether the straight line from a to b is over ground that lets you along it, square to square
local function LineClear(net, ax, ay, bx, by)
	local h = net.home
	if not (h and net.walls) then return true end
	local d = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
	local n = math.max(1, math.ceil(d / (h.side / 3)))
	local i, j = SquareOf(net, ax, ay)
	if not i then return false end
	local i0, j0 = floor((h.x - ay) / h.side) + 1, floor((h.y - ax) / h.side) + 1
	local oi, oj = i - i0, j - j0   -- (a start in a building: its line set off from the ground by it)
	for k = 1, n do
		local x, y = ax + (bx - ax) * k / n, ay + (by - ay) * k / n
		local i2, j2 = floor((h.x - y) / h.side) + 1 + oi, floor((h.y - x) / h.side) + 1 + oj
		if i2 ~= i or j2 ~= j then
			if math.abs(i2 - i) > 1 or math.abs(j2 - j) > 1 or not Open(net, i, j, i2 - i, j2 - j) then
				-- (the last square, a place in a building: near enough)
				if k == n and not HomeAt(net.walls, i2 - oi, j2 - oj) then return true end
				return false
			end
			i, j = i2, j2
		end
	end
	return true
end

--- the ground's ways about a point, out to `reach` yards of riding: every square that's got to
--- from it (back: every square it's got to from), each with the yards of its way. nil when the
--- network has no walls, or the point's on none of its ground
local function Walk(net, wx, wy, reach, back)
	local h = net.home
	if not (h and net.walls) then return end
	local i0, j0 = SquareOf(net, wx, wy)
	if not i0 then return end
	local side = h.side
	local dist, prev, heap, hn = {}, {}, {}, 0
	local function Push(key, d)
		hn = hn + 1
		local at = hn
		while at > 1 do
			local up = floor(at / 2)
			if heap[up][2] <= d then break end
			heap[at] = heap[up]
			at = up
		end
		heap[at] = { key, d }
	end
	local function Pop()
		local top = heap[1]
		local last = heap[hn]
		heap[hn] = nil
		hn = hn - 1
		if hn > 0 then
			local at = 1
			while true do
				local kid = at * 2
				if kid > hn then break end
				if kid < hn and heap[kid + 1][2] < heap[kid][2] then kid = kid + 1 end
				if heap[kid][2] >= last[2] then break end
				heap[at] = heap[kid]
				at = kid
			end
			heap[at] = last
		end
		return top
	end
	local k0 = i0 * WALK_KEY + j0
	local got = 0
	local function Spread()
	while hn > 0 do
		local top = Pop()
		local key, d = top[1], top[2]
		if d <= dist[key] then
			local i, j = floor(key / WALK_KEY), key % WALK_KEY
			for di = -1, 1 do
				for dj = -1, 1 do
					if di ~= 0 or dj ~= 0 then
						local i2, j2 = i + di, j + dj
						local nd = d + ((di ~= 0 and dj ~= 0) and side * 1.4142 or side)
						local k2 = i2 * WALK_KEY + j2
						if nd <= reach and nd < (dist[k2] or math.huge) then
							local ok
							if back then ok = Open(net, i2, j2, -di, -dj) else ok = Open(net, i, j, di, dj) end
							if ok then
								if not dist[k2] then got = got + 1 end
								dist[k2] = nd
								prev[k2] = key
								Push(k2, nd)
							end
						end
					end
				end
			end
		end
	end
	end
	dist[k0] = 0
	Push(k0, 0)
	Spread()
	-- (hardly anywhere got to: the place's own square is one the ground's shut about, a rock's
	-- top, a bank's foot, and it's stood by, not in. From the squares next to it, then)
	-- (only where you are: you're stood there, so there's a way off it. Where you're going may
	-- well be a ledge nothing gets up to)
	if got < WALK_FEW and not back then
		for di = -1, 1 do
			for dj = -1, 1 do
				local k2 = (i0 + di) * WALK_KEY + j0 + dj
				if (di ~= 0 or dj ~= 0) and not dist[k2] and HomeAt(net.walls, i0 + di, j0 + dj) then
					local nd = (di ~= 0 and dj ~= 0) and side * 1.4142 or side
					dist[k2] = nd
					prev[k2] = k0
					Push(k2, nd)
				end
			end
		end
		Spread()
	end
	return { dist = dist, prev = prev, net = net, x = wx, y = wy, back = back, i0 = i0, j0 = j0 }
end

--- the way of a Walk to a point: its yards, and the points it turns at between its two ends
--- (world, as it's ridden: from the Walk's place, or back to it). nil when the point wasn't got to
local function WalkTo(walk, wx, wy)
	local net = walk.net
	local h = net.home
	local i, j = SquareOf(net, wx, wy)
	if not i then return end
	local key = i * WALK_KEY + j
	if not walk.dist[key] then return end
	-- (from the point back to the Walk's place, square by square)
	local pts = { { wx, wy } }
	local at = walk.prev[key]
	local stop = walk.i0 * WALK_KEY + walk.j0
	while at and at ~= stop do
		local ai, aj = floor(at / WALK_KEY), at % WALK_KEY
		pts[#pts + 1] = { h.y - (aj - 0.5) * h.side, h.x - (ai - 0.5) * h.side }
		at = walk.prev[at]
	end
	pts[#pts + 1] = { walk.x, walk.y }
	-- (only where it turns)
	local keep = { [1] = true, [#pts] = true }
	local function Thin(a, b)
		local ax, ay, bx, by = pts[a][1], pts[a][2], pts[b][1], pts[b][2]
		local len = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
		local worst, mid = WALK_STRAY, nil
		for k = a + 1, b - 1 do
			local off
			if len < 1 then off = sqrt((pts[k][1] - ax) ^ 2 + (pts[k][2] - ay) ^ 2)
			else off = math.abs((bx - ax) * (ay - pts[k][2]) - (ax - pts[k][1]) * (by - ay)) / len end
			if off > worst then worst, mid = off, k end
		end
		if mid then
			keep[mid] = true
			Thin(a, mid)
			Thin(mid, b)
		end
	end
	Thin(1, #pts)
	local line, yards, lx, ly = {}, 0, nil, nil
	for k = 1, #pts do
		if keep[k] then
			if lx then yards = yards + sqrt((pts[k][1] - lx) ^ 2 + (pts[k][2] - ly) ^ 2) end
			lx, ly = pts[k][1], pts[k][2]
			line[#line + 1] = pts[k]
		end
	end
	-- (its ends aren't points of the way; and as it's ridden: a Walk back was followed from the
	-- point to the place, as it's ridden; a Walk out, the other way about)
	local mids = {}
	if walk.back then
		for k = 2, #line - 1 do mids[#mids + 1] = line[k] end
	else
		for k = #line - 1, 2, -1 do mids[#mids + 1] = line[k] end
	end
	return yards, mids
end

--- the nearest k nodes within r yards of a point (in zone, when given): { { i, yards }, ... },
--- nearest first
local function Near(net, wx, wy, r, k, zone, main)
	local out = {}
	local cx, cy, span = floor(wx / BUCKET), floor(wy / BUCKET), math.ceil(r / BUCKET)
	for dx = -span, span do
		for dy = -span, span do
			local g = net.grid[(cx + dx) * 100000 + (cy + dy)]
			for _, i in ipairs(g or {}) do
				-- (main: not a pocket's node, that nothing leads to)
				if (not zone or net.zone[i] == zone) and (not main or net.inc[i]) then
					local d = sqrt((net.x[i] - wx) ^ 2 + (net.y[i] - wy) ^ 2)
					if d <= r then out[#out + 1] = { i, d } end
				end
			end
		end
	end
	table.sort(out, function(a, b) return a[2] < b[2] end)
	for j = #out, k + 1, -1 do out[j] = nil end
	return out
end

-- whether the straight line between two points lies over ground the network reaches, all the
-- way (no building, rock or cliff's face on it: those are squares no node reaches). The first
-- and last few yards aren't looked at: a point may stand in a doorway
local LINE_SKIP = 25
local function LineOk(net, ax, ay, bx, by, n1, n2)
	local h = net.home
	if not h then return true end
	-- (n1, n2: the two ends' own nodes. The ground between is theirs alone, and they're one
	-- piece of ground, joined both ways: not a mesa's top and the floor under it)
	if n1 and n2 and n1 ~= n2 and not TwoWay(net, n1, n2) then return false end
	local d = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
	if d <= LINE_SKIP * 2 then return true end
	local n = math.ceil(d / (h.side * 0.5))
	for k = 0, n do
		local at = d * k / n
		if at >= LINE_SKIP and at <= d - LINE_SKIP then
			local x, y = ax + (bx - ax) * k / n, ay + (by - ay) * k / n
			local at2 = HomeAt(h, floor((h.x - y) / h.side) + 1, floor((h.y - x) / h.side) + 1)
			if not at2 or (n1 and at2 ~= n1 and at2 ~= n2) then return false end
		end
	end
	return true
end

-- the nodes a point joins the network at: the one that reaches it over the ground, then the
-- nearest others (k in all) the straight line to which is over reached ground. nil when the
-- network can't say (no home raster, or nothing reaches near the point)
local LEDGE_NEAR = 80   -- yards
local WALK_ROUND = 1.6   -- a way round to a node may be this many times as long as a node may be far
local DIRECT = 1200      -- yards: where you're going this near, and the ground between open and of a piece: straight there is a way too

-- whether the network's own way from one node to the next is as quick as open, level ground
-- would be ridden (not round a hill, up a slope, through water or down a drop): the ground
-- between them is then ground a straight line can be ridden over
local FLAT = 1.25
local function FlatTo(net, a, b)
	local yd = sqrt((net.x[a] - net.x[b]) ^ 2 + (net.y[a] - net.y[b]) ^ 2)
	for _, e in ipairs(net.adj[a] or {}) do
		if e.to == b then return not e.swum and not e.drop and e.cost <= yd / NET_RIDE * FLAT end
	end
	return false
end

-- the straight line between two points, over reached ground all the way, and that ground open
-- and of a piece: wherever it passes from one node's ground to another's, the network's own
-- way between the two is level going, both ways
local function LineChain(net, ax, ay, bx, by)
	local h = net.home
	if not h then return false end
	local d = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
	local n = math.max(1, math.ceil(d / (h.side * 0.5)))
	local last
	local okPair = {}
	for k = 0, n do
		local x, y = ax + (bx - ax) * k / n, ay + (by - ay) * k / n
		local at2 = HomeAt(h, floor((h.x - y) / h.side) + 1, floor((h.y - x) / h.side) + 1)
		local at = d * k / n
		if not at2 then
			if at >= LINE_SKIP and at <= d - LINE_SKIP then return false end
		else
			if last and at2 ~= last then
				local key = last * 100000 + at2
				if okPair[key] == nil then okPair[key] = FlatTo(net, last, at2) and FlatTo(net, at2, last) end
				if not okPair[key] then return false end
			end
			last = at2
		end
	end
	return true
end

-- whether a node is joined both ways to none of its neighbours: one on a ledge or a hilltop,
-- that ground is dropped onto from, not ridden back up to. Its squares of the home raster are
-- ordinary ground beneath it, the other nodes' as much as its own
local function Ledge(net, n)
	local c = net.ledge
	if not c then c = {} net.ledge = c end
	if c[n] == nil then
		-- (and no way off it is a fall: that's a mesa's top, a cliff's, its own ground, left by a
		-- lift or a jump)
		-- (one with no way off it at all isn't: a mesa's top, an island of ground, left by a lift)
		local lone = #(net.adj[n] or {}) > 0
		for _, e in ipairs(net.adj[n] or {}) do
			if e.drop or TwoWay(net, n, e.to) then lone = false break end
		end
		c[n] = lone
	end
	return c[n]
end

-- the straight line from a point to a node, over reached ground all the way, the ground of that
-- node or of ones joined both ways to it (or a ledge's, which is anyone's)
local function LineLoose(net, ax, ay, bx, by, hn, n2)
	local h = net.home
	if not h then return true end
	local d = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
	if d <= LINE_SKIP * 2 then return true end
	local n = math.ceil(d / (h.side * 0.5))
	local okAt = {}
	for k = 0, n do
		local at = d * k / n
		if at >= LINE_SKIP and at <= d - LINE_SKIP then
			local x, y = ax + (bx - ax) * k / n, ay + (by - ay) * k / n
			local at2 = HomeAt(h, floor((h.x - y) / h.side) + 1, floor((h.y - x) / h.side) + 1)
			if not at2 then return false end
			if okAt[at2] == nil then okAt[at2] = at2 == hn or at2 == n2 or TwoWay(net, at2, n2) or Ledge(net, at2) end
			if not okAt[at2] then return false end
		end
	end
	return true
end

-- mode: nil, a farming loop's spot (strictly its own ground). "start", where a route sets out;
-- "to", any other place of a route's. For those, when the point's own node is a ledge's (it
-- reaches the point by dropping to it; the point doesn't reach it, and nothing else may reach
-- the node): the network proper's nodes about it too, the line to which is over ground
local function Joins(net, wx, wy, r, k, zone, mode, walk)
	local hn, hd = Home(net, wx, wy)
	if not hn then return end
	-- (walk: where a route sets out or ends, the ground's own ways about it. Each node it joins,
	-- as below, is joined by a line the ground lets you along; or by the ground's way round to
	-- it, { node, yards, extra, points }; or, when there's neither, not at all. All of them shut:
	-- as below, the ground's word not taken)
	local function Checked(out)
		if not walk then return out end
		local kept = {}
		for _, c in ipairs(out) do
			local nx, ny = net.x[c[1]], net.y[c[1]]
			local clear
			if walk.back then clear = LineClear(net, nx, ny, wx, wy) else clear = LineClear(net, wx, wy, nx, ny) end
			if clear then
				kept[#kept + 1] = c
			else
				local yards, mids = WalkTo(walk, nx, ny)
				if yards and yards <= r * WALK_ROUND then kept[#kept + 1] = { c[1], yards, c[3], mids } end
			end
		end
		if #kept == 0 then return out end
		table.sort(kept, function(a, b) return a[2] < b[2] end)
		return kept
	end
	-- (a node nothing leads to or from, the hand's cut having taken its last way, or a pocket's
	-- the bake left on its own: no way to or from the point at all. The network proper about
	-- the point instead, not over a wall set by hand; the ground has its say below, Checked)
	local dead = mode ~= nil and not net.inc[hn] and #net.adj[hn] == 0
	local out = dead and {} or { { hn, hd } }
	local has = { [hn] = true }
	-- (as ever: its own node, and the others the ground between which is theirs alone. With no
	-- node of its own: the network proper's, that something leads to; not a pocket's)
	for _, c in ipairs(Near(net, wx, wy, r, k + 3, zone, dead or nil)) do
		if #out >= k then break end
		if not has[c[1]] and ((dead and not Route.HandCross(net, wx, wy, net.x[c[1]], net.y[c[1]]))
			or (net.hand and net.hand[c[1]]) or LineOk(net, wx, wy, net.x[c[1]], net.y[c[1]], hn, c[1])) then
			out[#out + 1] = c
			has[c[1]] = true
		end
	end
	-- (a ledge's point: those of the network proper too, marked as that, extra = true)
	local ledge = mode and not dead and Ledge(net, hn)
	if ledge then
		local n = 0
		for _, c in ipairs(Near(net, wx, wy, r, k + 3, zone, true)) do
			if n >= k then break end
			-- (the ones the ledge's own way down to is level going, in its zone: the ground under it)
			if not has[c[1]] and net.zone[c[1]] == net.zone[hn] and FlatTo(net, hn, c[1])
				and LineLoose(net, wx, wy, net.x[c[1]], net.y[c[1]], hn, c[1]) then
				out[#out + 1] = { c[1], c[2], true }
				has[c[1]] = true
				n = n + 1
			end
		end
		-- (setting out, the ledge itself a way off and nothing leading to it: not where you are,
		-- when there's other ground to set out over)
		if n > 0 and mode == "start" and not net.inc[hn] and hd > LEDGE_NEAR then table.remove(out, 1) end
	end
	table.sort(out, function(a, b) return a[2] < b[2] end)
	return Checked(out)
end

function Route._Dbg(ui, x, y, mode)
	local wx, wy, inst = World(ui, x / 100, y / 100)
	local net = Net(inst)
	local hn, hd = Home(net, wx, wy)
	local o = {}
	local function P(n)
		local zx, zy = HBD:GetZoneCoordinatesFromWorld(net.x[n], net.y[n], ui)
		return ("%d(%.1f,%.1f z%s%s%s)"):format(n, (zx or 0) * 100, (zy or 0) * 100, tostring(net.zone[n]), net.inc[n] and "" or " NOINC", Ledge(net, n) and " LEDGE" or "")
	end
	if not hn then return "no home" end
	o[#o + 1] = "home " .. P(hn) .. (" %.0fyd"):format(hd)
	for _, e in ipairs(net.adj[hn] or {}) do
		o[#o + 1] = ("   -> %s %ds%s%s%s"):format(P(e.to), e.cost, TwoWay(net, hn, e.to) and " 2way" or " 1way", e.drop and (" drop" .. e.drop) or "", e.swum and " swum" or "")
	end
	local j = Joins(net, wx, wy, 600, 3, nil, mode)
	for _, c in ipairs(j or {}) do o[#o + 1] = "   join " .. P(c[1]) .. (" %.0fyd %s"):format(c[2], tostring(c[4] or "both")) end
	return table.concat(o, string.char(10))
end

--------------------------------------------------------------------------------
-- The other faction's towns: where its innkeepers, flight masters, vendors and trainers stand
-- together (QuestieDB's own: who each is friendly to). A way through one counts many times its
-- riding, so routes and farming loops go round; unless you start in it or are headed there
--------------------------------------------------------------------------------

local FOE_JOIN = 150     -- yards: NPCs this near each other are one town
local FOE_MIN = 4        -- of them, at least, to be a town (not a lone camp's vendor)
local FOE_PAD = 120      -- yards past its outermost NPC: its guards' reach, and a little
local FOE_WARN = 120     -- yards past that: a way this near one says so
local FOE_AVOID = 8      -- times its riding a way through one counts
local foes               -- { [continent] = { { x, y, r }, ... } }, once Questie's data is read
local FOE_CELL = 500     -- yards: the squares the towns are kept by
local FOE_EDGE = 1300    -- yards: an edge of the network strays no further than this from its ends
local foeNear, foeAbout = {}, {}
local NO_FOES = {}

local function Foes(inst)
	if not foes then
		if not (ns.Index and ns.Index.done and ns.Index.DB and ns.UiMapFor) then return {} end
		foes = {}
		local theirs = ns.faction == "Horde" and "A" or ns.faction == "Alliance" and "H" or nil
		local DB = ns.Index.DB()
		local groups = {}
		for _, e in ipairs(theirs and DB and ns.Index.entries or {}) do
			if e.fac == theirs and (e.flags or 0) ~= 0 then
				for areaId, list in pairs(ns.Index.Spawns(DB, e.id) or {}) do
					local ui = type(list) == "table" and ns.UiMapFor(areaId)
					local sp = ui and list[1]
					if sp and type(sp[1]) == "number" and type(sp[2]) == "number" and sp[1] >= 0 then
						local x, y, inst2 = World(ui, sp[1] / 100, sp[2] / 100)
						if x and inst2 then
							groups[inst2] = groups[inst2] or {}
							local into
							for _, g in ipairs(groups[inst2]) do
								if (g.x - x) ^ 2 + (g.y - y) ^ 2 <= FOE_JOIN * FOE_JOIN then into = g break end
							end
							if not into then
								into = { x = x, y = y, pts = {} }
								tinsert(groups[inst2], into)
							end
							tinsert(into.pts, { x, y })
							local n = #into.pts
							into.x, into.y = into.x + (x - into.x) / n, into.y + (y - into.y) / n
						end
					end
				end
			end
		end
		for inst2, list in pairs(groups) do
			foes[inst2] = {}
			for _, g in ipairs(list) do
				if #g.pts >= FOE_MIN then
					local far = 0
					for _, pt in ipairs(g.pts) do far = max(far, sqrt((pt[1] - g.x) ^ 2 + (pt[2] - g.y) ^ 2)) end
					tinsert(foes[inst2], { x = g.x, y = g.y, r = far + FOE_PAD })
				end
			end
		end
		-- (by the square they reach: a point looks in its own square's few, not at every town.
		-- near: within warning's reach of the square; about: within an edge's length of it)
		for inst2, list in pairs(foes) do
			local near, about = {}, {}
			foeNear[inst2], foeAbout[inst2] = near, about
			for _, t in ipairs(list) do
				local reach = t.r + FOE_WARN + FOE_CELL * 0.15   -- (and a stretch's step between looks)
				for cx = floor((t.x - reach) / FOE_CELL), floor((t.x + reach) / FOE_CELL) do
					for cy = floor((t.y - reach) / FOE_CELL), floor((t.y + reach) / FOE_CELL) do
						local k = cx * 100000 + cy
						near[k] = near[k] or {}
						tinsert(near[k], t)
					end
				end
				reach = t.r + FOE_EDGE
				for cx = floor((t.x - reach) / FOE_CELL), floor((t.x + reach) / FOE_CELL) do
					for cy = floor((t.y - reach) / FOE_CELL), floor((t.y + reach) / FOE_CELL) do
						about[cx * 100000 + cy] = true
					end
				end
			end
		end
	end
	return foes[inst] or NO_FOES
end

-- the towns that may reach a point: its square's
local function FoesBy(inst, wx, wy)
	Foes(inst)
	local near = foeNear[inst]
	return near and near[floor(wx / FOE_CELL) * 100000 + floor(wy / FOE_CELL)] or NO_FOES
end

-- the other faction's town a point is in, or nil
local function FoeAt(inst, wx, wy)
	for _, t in ipairs(FoesBy(inst, wx, wy)) do
		if (t.x - wx) ^ 2 + (t.y - wy) ^ 2 <= t.r * t.r then return t end
	end
end

-- the town a straight stretch passes within extra yards of (but one), or nil: the towns of the
-- squares along it, each measured
local function FoeOnStretch(inst, ax, ay, bx, by, extra, but)
	local dx, dy = bx - ax, by - ay
	local l2 = dx * dx + dy * dy
	local steps = math.ceil(sqrt(l2) / (FOE_CELL * 0.25))
	for k = 0, steps do
		local f = steps > 0 and k / steps or 0
		for _, t in ipairs(FoesBy(inst, ax + dx * f, ay + dy * f)) do
			if t ~= but then
				local u = l2 > 0 and max(0, min(1, ((t.x - ax) * dx + (t.y - ay) * dy) / l2)) or 0
				local reach = t.r + extra
				if (t.x - ax - u * dx) ^ 2 + (t.y - ay - u * dy) ^ 2 <= reach * reach then return t end
			end
		end
	end
end

-- the towns a network edge out of node a passes through (kept, by the edge): a list, or false
local edgeFoes = setmetatable({}, { __mode = "k" })   -- (by the edge: gone with it, when its network's let go)
local function EdgeFoes(net, inst, a, e)
	if edgeFoes[e] ~= nil then return edgeFoes[e] end
	if not foes then Foes(inst) end
	if not foes then return false end   -- (Questie's data not read yet: asked again later)
	-- (no town anywhere about either end: none on the way, its points not even read)
	local about = foeAbout[inst]
	if not about or not (about[floor(net.x[a] / FOE_CELL) * 100000 + floor(net.y[a] / FOE_CELL)]
		or about[floor(net.x[e.to] / FOE_CELL) * 100000 + floor(net.y[e.to] / FOE_CELL)]) then
		edgeFoes[e] = false
		return false
	end
	local pts = { net.x[a], net.y[a] }
	local m = e.mids and Mids(e)
	if m then
		if e.fwd then for k = 1, #m do pts[#pts + 1] = m[k] end
		else for k = #m - 1, 1, -2 do pts[#pts + 1] = m[k] pts[#pts + 1] = m[k + 1] end end
	end
	pts[#pts + 1] = net.x[e.to]
	pts[#pts + 1] = net.y[e.to]
	local hit
	for k = 1, #pts - 3, 2 do
		local t = FoeOnStretch(inst, pts[k], pts[k + 1], pts[k + 2], pts[k + 3], 0)
		if t then
			hit = hit or {}
			local have = false
			for _, h in ipairs(hit) do if h == t then have = true break end end
			if not have then hit[#hit + 1] = t end
		end
	end
	edgeFoes[e] = hit or false
	return edgeFoes[e]
end

-- how many times its riding an edge counts: more through a town of the other faction (but one
-- of allow's: the town you're in, or are going to)
local function FoeWeight(net, inst, a, e, allow)
	local list = EdgeFoes(net, inst, a, e)
	if not list then return 1 end
	for _, t in ipairs(list) do
		if not (allow and allow[t]) then return FOE_AVOID end
	end
	return 1
end

--- whether a point on a zone's map (0..100) is in a town of the other faction
function Route.FoeNear(ui, x, y)
	local wx, wy, inst = World(ui, x / 100, y / 100)
	return wx and FoeAt(inst, wx, wy) ~= nil or false
end

--- the town of the other faction a way passes near (its points on zone maps, 0..100: { ui, x, y }
--- each, straight from one to the next), by name ("Southshore"); nil when it passes none.
--- but: a town not to speak of (the one you're headed for)
function Route.FoeOnWay(pts, but)
	local last, lastX, lastY, lastInst
	for _, p in ipairs(pts) do
		local wx, wy, inst = World(p.ui, p.x / 100, p.y / 100)
		if wx then
			local ax, ay = wx, wy
			if last and lastInst == inst then ax, ay = lastX, lastY end
			local t = FoeOnStretch(inst, ax, ay, wx, wy, FOE_WARN, but)
			if t then
				local zx, zy = HBD:GetZoneCoordinatesFromWorld(t.x, t.y, p.ui, true)
				return zx and PlaceName(p.ui, zx, zy) or ns.ZoneName(p.ui) or "?"
			end
			last, lastX, lastY, lastInst = true, wx, wy, inst
		end
	end
end
Route.FoeAt = function(ui, x, y)
	local wx, wy, inst = World(ui, x / 100, y / 100)
	return wx and FoeAt(inst, wx, wy) or nil
end

-- whether a square of the home raster (row i, square j, from 1) is water to swim in
local function WetAt(h, i, j)
	if not h.wetAll or i < 1 or j < 1 then return false end
	if not h.wetStarts then
		-- (where each row starts in the one string, as the home rows': read when first asked)
		local starts, n, at = {}, 0, 1
		while true do
			n = n + 1
			starts[n] = at
			local bar = h.wetAll:find("|", at, true)
			if not bar then break end
			at = bar + 1
		end
		starts[n + 1] = #h.wetAll + 2
		h.wetStarts, h.wetN, h.wetRows = starts, n, {}
	end
	if i > h.wetN then return false end
	local row = h.wetRows[i]
	if not row then
		-- (runs: dry, wet, dry... squares, in base 36; where each ends)
		row = {}
		local at = 0
		for len in h.wetAll:sub(h.wetStarts[i], h.wetStarts[i + 1] - 2):gmatch("%w+") do
			at = at + tonumber(len, 36)
			row[#row + 1] = at
		end
		h.wetRows[i] = row
	end
	for k = 1, #row do
		if j <= row[k] then return k % 2 == 0 end
	end
	return false
end

--- a way (its points on a zone's map, 0..100: { x, y } each, both ends too) with every stretch
--- that's in a town of the other faction taken round the town's edge instead: the shorter side
--- that's dry ground the network reaches. The rest of it stays as it was (a farming loop's own
--- way over the terrain). Its points between the ends, and its yards; nil when an end's in a
--- town, or there's no such way round one. other: the longer side, where both will do (the same
--- way, when only one does)
local ROUND_PAD = 40      -- yards outside the town's reach
local ROUND_STEP = 20     -- yards: how finely the way's looked along
local ROUND_WADE = 80     -- yards of it, at most, swum
function Route.RoundTowns(ui, pts, other)
	local W, inst = {}, nil
	for i, p in ipairs(pts) do
		local wx, wy, wi = World(ui, p.x / 100, p.y / 100)
		if not wx then return end
		W[i], inst = { wx, wy, true }, wi
	end
	local net = inst and Net(inst)
	local h = net and net.home
	if not (h and h.wetAll) or #W < 2 then return end
	if FoeAt(inst, W[1][1], W[1][2]) or FoeAt(inst, W[#W][1], W[#W][2]) then return end
	-- (the way's own points, and ones between them every few yards)
	local D = {}
	for i = 1, #W - 1 do
		local a, b = W[i], W[i + 1]
		D[#D + 1] = a
		local n = math.ceil(sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) / ROUND_STEP)
		for k = 1, n - 1 do D[#D + 1] = { a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n } end
	end
	D[#D + 1] = W[#W]
	-- (a straight stretch: the yards of it that are swum; nil when some of it isn't reached at all)
	local function Swum(a, b)
		local d = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local n = max(1, math.ceil(d / 12))
		local wet = 0
		for k = 0, n do
			local x, y = a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n
			local i, j = floor((h.x - y) / h.side) + 1, floor((h.y - x) / h.side) + 1
			if not HomeAt(h, i, j) then return end
			if WetAt(h, i, j) then wet = wet + d / n end
		end
		return wet
	end
	local function In(t, p) return (t.x - p[1]) ^ 2 + (t.y - p[2]) ^ 2 <= t.r * t.r end
	local out, i = {}, 1
	while i <= #D do
		local p = D[i]
		local t = FoeAt(inst, p[1], p[2])
		if not t then
			if p[3] then out[#out + 1] = p end
			i = i + 1
		else
			-- (all of it that's in this town, to where it's last out of it: round in one go)
			local j = i
			for k = #D, i, -1 do
				if In(t, D[k]) then j = k + 1 break end
			end
			local pin, pout = D[i - 1], D[j]
			local ta, tb = math.atan2(pin[2] - t.y, pin[1] - t.x), math.atan2(pout[2] - t.y, pout[1] - t.x)
			local step = math.pi / 8
			local R = (t.r + ROUND_PAD) / math.cos(step / 2)
			local best, bestLen
			for side = 1, 2 do
				local sweep = tb - ta
				if side == 1 then while sweep < 0 do sweep = sweep + 2 * math.pi end
				else while sweep > 0 do sweep = sweep - 2 * math.pi end end
				local steps = max(1, math.ceil(math.abs(sweep) / step))
				local arc, ok, len, last, wet = {}, true, 0, pin, 0
				-- (from where it goes in, by the edge's points between, to where it comes out)
				for k = 1, steps do
					local q = pout
					if k < steps then
						local a = ta + sweep * k / steps
						q = { t.x + R * math.cos(a), t.y + R * math.sin(a) }
					end
					local w = not FoeAt(inst, q[1], q[2]) and Swum(last, q)
					-- (a river swum across, yes; the sea off its docks, no)
					wet = wet + (w or 0)
					if not w or wet > ROUND_WADE then ok = false break end
					len = len + sqrt((q[1] - last[1]) ^ 2 + (q[2] - last[2]) ^ 2)
					if k < steps then arc[#arc + 1] = q end
					last = q
				end
				if ok and (not bestLen or (len < bestLen) ~= (other or false)) then best, bestLen = arc, len end
			end
			if not best then return end
			if not pin[3] then pin.cut = true out[#out + 1] = pin end
			for _, q in ipairs(best) do out[#out + 1] = q end
			if not pout[3] then pout.cut = true end
			pout[3] = true
			i = j
		end
	end
	-- (where it went in and came out: left out, when the way's as good straight past them)
	for k = #out - 1, 2, -1 do
		local a, b = out[k - 1], out[k + 1]
		if out[k].cut and not FoeOnStretch(inst, a[1], a[2], b[1], b[2], 0) then
			local w = Swum(a, b)
			if w and w <= ROUND_WADE then table.remove(out, k) end
		end
	end
	local via, yards = {}, 0
	for k = 2, #out do
		yards = yards + sqrt((out[k][1] - out[k - 1][1]) ^ 2 + (out[k][2] - out[k - 1][2]) ^ 2)
	end
	for k = 2, #out - 1 do
		local x, y = HBD:GetZoneCoordinatesFromWorld(out[k][1], out[k][2], ui, true)
		if x then via[#via + 1] = { ui = ui, x = x * 100, y = y * 100 } end
	end
	return via, yards
end

--- whether a route can be planned on this continent (its network's there)
function Route.HasNet(inst) return Net(inst) ~= nil end

--- the way over the ground between two points on a zone's map (0..100), by the network: round
--- cliffs, mountains and walls. Its points between (on that map) and its seconds riding (a 60%
--- mount); nil when it's a short hop (straight is it) or the network can't join them
local WAY_STRAIGHT = 220       -- yards: a hop this short, straight
local WAY_ABOUT = 1500         -- yards about its two ends (their distance apart, when that's more) a way's looked for in
local WAY_OPEN = 700           -- yards: a longer one too, when the line's over ground the network reaches all the way
function Route.GroundWay(ui, x1, y1, x2, y2)
	local ax, ay, ainst = World(ui, x1 / 100, y1 / 100)
	local bx, by, binst = World(ui, x2 / 100, y2 / 100)
	if not (ax and bx) or ainst ~= binst then return end
	if sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) < WAY_STRAIGHT then return end
	local net = Net(ainst)
	if not net then return end
	local zone = ZoneOf(ui)
	local A = Near(net, ax, ay, LINK_R, LINK_K, zone)
	local B = Near(net, bx, by, LINK_R, LINK_K, zone)
	-- (each end's own node, the one that reaches it over the ground, when the network says)
	A = Joins(net, ax, ay, LINK_R, LINK_K, zone) or A
	B = Joins(net, bx, by, LINK_R, LINK_K, zone) or B
	-- (a hop over open ground, not far: straight is it, not out to the network and back)
	-- (the other faction's towns: gone round, but one an end of it is in)
	local allow, within = {}, false
	for _, t in ipairs({ FoeAt(ainst, ax, ay) or false, FoeAt(ainst, bx, by) or false }) do
		if t then allow[t], within = true, true end
	end
	-- (and not straight through one, either)
	local town = not within and FoeOnStretch(ainst, ax, ay, bx, by, 0)
	local ha, hb = Home(net, ax, ay), Home(net, bx, by)
	if not town and ha and hb and sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) < WAY_OPEN and LineOk(net, ax, ay, bx, by, ha, hb) then return end
	if #A == 0 or #B == 0 then return end
	local toB = {}
	for _, b in ipairs(B) do toB[b[1]] = b[2] end
	local reach = max(WAY_ABOUT, sqrt((ax - bx) ^ 2 + (ay - by) ^ 2))
	local bx0, bx1 = min(ax, bx) - reach, max(ax, bx) + reach
	local by0, by1 = min(ay, by) - reach, max(ay, by) + reach
	local function Edges(u)
		local out = {}
		if u == 1 then
			for _, a in ipairs(A) do out[#out + 1] = { to = a[1] + 2, cost = a[2] / NET_RIDE * GROUND_DETOUR } end
			return out
		end
		if u == 2 then return out end
		local i = u - 2
		for _, e in ipairs(net.adj[i]) do
			-- (only about the two ends: a hop inside a zone isn't looked for across the continent)
			local nx, ny = net.x[e.to], net.y[e.to]
			if nx >= bx0 and nx <= bx1 and ny >= by0 and ny <= by1 then
				out[#out + 1] = { to = e.to + 2, cost = e.cost, net = e, pick = e.cost * FoeWeight(net, ainst, i, e, allow) }
			end
		end
		if toB[i] then out[#out + 1] = { to = 2, cost = toB[i] / NET_RIDE * GROUND_DETOUR } end
		return out
	end
	local path, secs = Route.Search(net.n + 2, Edges)
	if not path then return end
	local via = {}
	local function Pt(wx, wy)
		local x, y = HBD:GetZoneCoordinatesFromWorld(wx, wy, ui, true)
		if x then via[#via + 1] = { ui = ui, x = x * 100, y = y * 100 } end
	end
	for _, p in ipairs(path) do
		local e = p.edge and p.edge.net
		if e and e.mids then
			local m = Mids(e)
			if e.fwd then for k = 1, #m, 2 do Pt(m[k], m[k + 1]) end
			else for k = #m - 1, 1, -2 do Pt(m[k], m[k + 1]) end end
		end
		if p.to > 2 then Pt(net.x[p.to - 2], net.y[p.to - 2]) end
	end
	return via, secs
end

--------------------------------------------------------------------------------
-- The planner: the quickest way through places (Dijkstra, a heap). Pure: it's given how many
-- places there are and what leads out of each
--------------------------------------------------------------------------------

--- n places, 1 the start and 2 the goal; edges(u) -> list of { to, cost, kind, leg?, pick? }
--- (pick: what it counts in choosing, when more than its cost). Returns the path as
--- { { from, to, kind, cost, leg? }, ... } and its seconds, or nil
function Route.Search(n, edges)
	local dist, prev, how, done = {}, {}, {}, {}
	local heap, hn = {}, 0
	local function Push(d, v)
		hn = hn + 1
		local i = hn
		heap[i] = { d, v }
		while i > 1 do
			local p = floor(i / 2)
			if heap[p][1] <= heap[i][1] then break end
			heap[p], heap[i] = heap[i], heap[p]
			i = p
		end
	end
	local function Pop()
		local top = heap[1]
		heap[1] = heap[hn]
		heap[hn] = nil
		hn = hn - 1
		local i = 1
		while true do
			local l, r, s = 2 * i, 2 * i + 1, i
			if l <= hn and heap[l][1] < heap[s][1] then s = l end
			if r <= hn and heap[r][1] < heap[s][1] then s = r end
			if s == i then break end
			heap[s], heap[i] = heap[i], heap[s]
			i = s
		end
		return top
	end
	dist[1] = 0
	Push(0, 1)
	while hn > 0 do
		local top = Pop()
		local u = top[2]
		if not done[u] then
			done[u] = true
			if u == 2 then break end
			for _, e in ipairs(edges(u) or {}) do
				local v = e.to
				if not done[v] then
					local d = dist[u] + (e.pick or e.cost)
					if d < (dist[v] or math.huge) then
						dist[v], prev[v], how[v] = d, u, e
						Push(d, v)
					end
				end
			end
		end
	end
	if not dist[2] then return end
	local path, v, total = {}, 2, 0
	while prev[v] do
		local e = how[v]
		table.insert(path, 1, { from = prev[v], to = v, kind = e.kind, cost = e.cost, leg = e.leg, edge = e })
		total = total + e.cost
		v = prev[v]
	end
	return path, total
end

--------------------------------------------------------------------------------
-- The places for a route from you to a marker: you, the marker, the flight paths you know,
-- the docks and towers, your inn, the lifts, gates, bridges and tunnels between zones; and
-- the network's nodes of each continent, which the rest join at their nearest
--------------------------------------------------------------------------------

local function Node(ui, x, y, extra)   -- x, y 0..1
	local wx, wy, inst = World(ui, x, y)
	if not wx then return end
	local n = { ui = ui, x = x, y = y, wx = wx, wy = wy, inst = inst, zone = ZoneOf(ui) }
	for k, v in pairs(extra or {}) do n[k] = v end
	return n
end

--- the quickest way to d (a marker's details: ui, x, y 0..100, name): steps, and seconds; nil
--- when there's none, or riding straight there is it. timeOnly: only the seconds (nil, secs),
--- straight ride or not
function Route.Plan(d, timeOnly, loose)
	if not (HBD and HBD.GetPlayerWorldPosition) then return end
	local px, py, pinst = HBD:GetPlayerWorldPosition()
	if not px then return end
	local here = ns.PlayerMap and ns.PlayerMap()
	local hz = here and ZoneOf(here) or 0
	local goal = Node(d.ui, d.x / 100, d.y / 100, { goal = true, name = d.name })
	if not goal then return end
	local speed = GroundSpeed()
	local goalZone = goal.zone
	local function ZoneDanger(z) return (z == goalZone or z == 0) and 1 or Danger(z) end
	-- (the other faction's towns: gone round, but the one you're in or are headed for)
	local foeAllow = {}
	for _, t in ipairs({ FoeAt(pinst, px, py) or false, FoeAt(goal.inst, goal.wx, goal.wy) or false }) do
		if t then foeAllow[t] = true end
	end

	-- the places: you and the marker first, then the rest; the networks' nodes after them all
	local places = { { wx = px, wy = py, inst = pinst, zone = hz, start = true }, goal }
	local special = {}   -- (edges out of each place that isn't a network node)
	local function Add(n) places[#places + 1] = n return #places end
	local function Link(a, b, cost, kind, leg, pick, pts)
		special[a] = special[a] or {}
		special[a][#special[a] + 1] = { to = b, cost = cost, kind = kind, leg = leg, pick = pick, pts = pts }
	end
	for _, f in ipairs(FlightNodes()) do
		if OursFlight(f) then
			-- (one you don't have, but right by you: picked up on the way, when flying from it's
			-- the quicker. Whether or not flight paths are being picked up along routes)
			local fresh = not Known(f) and f.inst == pinst and sqrt((f.wx - px) ^ 2 + (f.wy - py) ^ 2) <= FM_AT_HAND
			if fresh or Known(f) then
				Add({ ui = f.ui, x = f.x, y = f.y, wx = f.wx, wy = f.wy, inst = f.inst, zone = f.ui, fm = true, name = f.name,
					fresh = fresh or nil })
			end
		end
	end
	local fms = {}
	for i, p in ipairs(places) do if p.fm then fms[#fms + 1] = i end end
	local docks = {}
	local function Dock(ui, x, y)
		local key = ("%d:%.1f:%.1f"):format(ui, x, y)
		if not docks[key] then
			local n = Node(ui, x / 100, y / 100, { dock = true })
			if not n then return end
			docks[key] = Add(n)
		end
		return docks[key]
	end
	local side = ns.faction == "Alliance" and "A" or ns.faction == "Horde" and "H" or nil
	for _, l in ipairs(LEGS) do
		if not l[8] or l[8] == side then
			local a, b = Dock(l[1], l[2], l[3]), Dock(l[4], l[5], l[6])
			local secs = l[9] or TRANSPORT_COST[l[7]] or 240
			if a and b then Link(a, b, secs, "transport", l, secs + CHANGE_PENALTY) end
		end
	end
	-- (the ways the network hasn't a link for: their two ends, joined each way)
	local wayEnds = {}   -- (an end two ways share: the one place, so one leads on to the other)
	local function WayEnd(n, ui, x, y)
		local key = ("%d:%.1f:%.1f"):format(ui, x, y)
		if not wayEnds[key] then wayEnds[key] = Add(n) end
		return wayEnds[key]
	end
	for _, w in ipairs(WAYS) do
		local a, b = Node(w[1], w[2] / 100, w[3] / 100, { way = true }), Node(w[4], w[5] / 100, w[6] / 100, { way = true })
		if a and b and (a.inst == pinst or a.inst == goal.inst) then
			local ia, ib = WayEnd(a, w[1], w[2], w[3]), WayEnd(b, w[4], w[5], w[6])
			Link(ia, ib, w[7], "ride")
			Link(ib, ia, w[7], "ride")
		end
	end
	local inn = HearthSpot()
	if inn then
		local n = Node(inn.ui, inn.x, inn.y, { inn = true, name = inn.name })
		if n then Link(1, Add(n), HEARTH_COST, "hearth", nil, HEARTH_COST + CHANGE_PENALTY) end
	end
	-- the crossings the terrain can't tell: a lift, a gate, a tunnel's mouth, a ramp's foot (one
	-- point, in both zones: it joins the network on each side)
	local gates = {}   -- (a city's: what its places join)
	for _, e in ipairs(EXITS) do
		if e[5] then
			local n = Node(e[1], e[2] / 100, e[3] / 100, { cross = true, via = e[5], zone = e[1], into = e[4], reach = e[6] })
			if n then
				local i = Add(n)
				if e[5] == "lift" or e[5] == "gate" then
					gates[e[4]] = gates[e[4]] or {}
					gates[e[4]][#gates[e[4]] + 1] = i
					gates[e[1]] = gates[e[1]] or {}   -- (the gate seen from outside, too)
				end
			end
		end
	end

	-- (an end of a way right by where you stand, where you're going, a dock, a flight master or
	-- a gate: stepped onto from there, not by way of the network's nearest node and back)
	do
		local nPlaces = #places
		local isEnd = {}
		for _, ie in pairs(wayEnds) do isEnd[ie] = true end
		for ie in pairs(isEnd) do
			local e = places[ie]
			for ip = 1, nPlaces do
				local q = places[ip]
				if not isEnd[ip] and q.inst == e.inst and q.wx then
					local yd = sqrt((q.wx - e.wx) ^ 2 + (q.wy - e.wy) ^ 2)
					if yd <= WAY_HOP then
						Link(ip, ie, yd * 1.2 / speed, "ride")
						Link(ie, ip, yd * 1.2 / speed, "ride")
					end
				end
			end
		end
	end

	-- the networks, after every other place
	local base, netOf = {}, {}
	local nSpecial = #places
	local total = nSpecial
	for _, inst in ipairs({ pinst, goal.inst }) do
		if base[inst] == nil then
			local net = Net(inst)
			if net then
				base[inst] = total
				netOf[inst] = net
				total = total + net.n
			else
				base[inst] = false
			end
		end
	end
	if not (netOf[pinst] and netOf[goal.inst]) then return end

	-- (a place close by you, or by where you're going, a flight master, a dock, a lift's foot:
	-- straight to it and from it, over ground that's one piece with yours; not out to the network
	-- and back for the sake of 50 yards)
	local NEARBY = 450
	-- (the ground's own ways about you, and about where you're going: out from you, in to it)
	local walks = {}
	for _, endp in ipairs({ 1, 2 }) do
		local me = places[endp]
		local net = netOf[me.inst]
		if net and net.walls and not CITY[me.zone] and not timeOnly then
			local reach = LINK_R * WALK_ROUND
			if me.inst == goal.inst and places[1].zone == goal.zone and endp == 1 then
				local yd = sqrt((goal.wx - me.wx) ^ 2 + (goal.wy - me.wy) ^ 2)
				if yd <= DIRECT then reach = max(reach, yd * WALK_ROUND + 100) end
			end
			walks[endp] = Walk(net, me.wx, me.wy, reach, endp == 2)
		end
	end
	for _, endp in ipairs({ 1, 2 }) do
		local me = places[endp]
		local net = netOf[me.inst]
		local hme = net and not CITY[me.zone] and Home(net, me.wx, me.wy)
		if hme then
			for i = 3, nSpecial do
				local p = places[i]
				if p.inst == me.inst and not p.cross and not CITY[p.zone] then
					local yd = sqrt((p.wx - me.wx) ^ 2 + (p.wy - me.wy) ^ 2)
					if yd <= NEARBY and LineOk(net, me.wx, me.wy, p.wx, p.wy, hme, (Home(net, p.wx, p.wy))) then
						-- (and the ground lets you along the line; or round, by its own way)
						local pts
						local w = walks[endp]
						if w then
							local clear
							if endp == 1 then clear = LineClear(net, me.wx, me.wy, p.wx, p.wy) else clear = LineClear(net, p.wx, p.wy, me.wx, me.wy) end
							if not clear then
								local wyd, mids = WalkTo(w, p.wx, p.wy)
								if wyd and wyd <= NEARBY * WALK_ROUND then yd, pts = wyd, mids else yd = nil end
							end
						end
						if yd then
							local cost = yd * PathFactor(p.zone) / speed
							if endp == 1 then Link(1, i, cost, "ride", nil, nil, pts) else Link(i, 2, cost, "ride", nil, nil, pts) end
						end
					end
				end
			end
		end
	end

	-- (where you're going itself, in your zone, not far, and over open ground that's one piece
	-- with yours: straight there, weighed against the network's way round by its nodes)
	do
		local me = places[1]
		local net = netOf[me.inst]
		if net and me.inst == goal.inst and me.zone == goal.zone and not CITY[me.zone] then
			local yd = sqrt((goal.wx - me.wx) ^ 2 + (goal.wy - me.wy) ^ 2)
			local w = walks[1]
			if yd <= DIRECT and not w then
				if LineChain(net, me.wx, me.wy, goal.wx, goal.wy) then Link(1, 2, yd * PathFactor(goal.zone) / speed, "ride") end
			elseif yd <= DIRECT then
				-- (the ground's own word on it: the line when it's clear, or its way round: up the
				-- hill's one side that's climbed, not at its face)
				if LineClear(net, me.wx, me.wy, goal.wx, goal.wy) then
					if LineChain(net, me.wx, me.wy, goal.wx, goal.wy) then Link(1, 2, yd * PathFactor(goal.zone) / speed, "ride") end
				else
					local wyd, mids = WalkTo(w, goal.wx, goal.wy)
					if wyd then Link(1, 2, wyd * PathFactor(goal.zone) / speed, "ride", nil, nil, mids) end
				end
			end
		end
	end

	-- what joins each place to the network: the nearest nodes (a city's places: its gates)
	local joins = {}
	local function Join(i)
		if joins[i] then return joins[i] end
		local p, out = places[i], {}
		joins[i] = out
		local net = netOf[p.inst]
		if not net then return out end
		if CITY[p.zone] and not p.cross and gates[p.zone] then
			for _, g in ipairs(gates[p.zone]) do
				local q = places[g]
				if q.inst == p.inst then
					local yd = sqrt((p.wx - q.wx) ^ 2 + (p.wy - q.wy) ^ 2)
					out[#out + 1] = { to = g, cost = yd * PathFactor(p.zone) / speed, kind = "ride", link = true }
				end
			end
			return out
		end
		-- (a place that's no crossing: the node that reaches it over the ground, when the network
		-- says which. Not the nearest by the map, across a cliff or a wall)
		if not p.cross then
			local found = Joins(net, p.wx, p.wy, LINK_R, LINK_K, nil, p.start and "start" or "to", walks[i])
			-- (where you're going is ground nothing's found a way into: a walled town's inside, a
			-- yard. The nearest of the network proper too, then: the last of it by eye, not no route)
			-- (a goal's, as ever; a start's too on the second pass, when the first found no way out
			-- of where you stand: a village in a pocket of the ground the network never reached)
			if found and (p.goal or (loose and p.start)) then
				local main = false
				-- (a node of the hand's own isn't the network proper: its one link may be the long
				-- way in, and the nearest by eye the usual one. Nor a ledge's, that reaches the place
				-- by dropping to it: a way to the ledge is no way to the place)
				for _, near in ipairs(found) do if net.inc[near[1]] and not near[3] and not (net.hand and net.hand[near[1]]) and not Ledge(net, near[1]) then main = true break end end
				-- (loose: no way was found to it at all, the first time. Asked again, with more of
				-- the nodes about it)
				if not main or loose then
					-- (by eye, but not through a wall set by hand: not into a walled valley over its rim.
					-- A few more than the nearest: a ledge's node or the hand's own may be nearest, and no
					-- way in by eye, and the usual way in a little further off)
					local want = LINK_K * 2
					local n, got = 0, 0
					for _, near in ipairs(Near(net, p.wx, p.wy, LINK_R, want * 2, nil, true)) do
						if got >= want and n >= LINK_K then break end
						local j = near[1]
						if not (net.hand and net.hand[j]) and not Route.HandCross(net, p.wx, p.wy, net.x[j], net.y[j]) then
							found[#found + 1] = near
							got = got + 1
							if not Ledge(net, j) then n = n + 1 end
						end
					end
				end
			end
			if Route.debugJoins and found then
				local t = {}
				for _, near in ipairs(found) do t[#t + 1] = ("%d(%.0fyd%s%s%s)"):format(near[1], near[2], near[3] and " extra" or "", net.inc[near[1]] and "" or " noinc", Ledge(net, near[1]) and " ledge" or "") end
				print(("JOIN place %d goal=%s start=%s loose=%s: %s"):format(i, tostring(p.goal), tostring(p.start), tostring(loose), table.concat(t, " ")))
			end
			if found then
				for _, near in ipairs(found) do
					local j, yd = near[1], near[2]
					local nz = net.zone[j]
					local cost = yd * PathFactor(nz) / speed
					-- (pts: a way round, its points as they're ridden)
					out[#out + 1] = { to = base[p.inst] + j, cost = cost, kind = "ride", link = true, pick = cost * ZoneDanger(nz), pts = near[4] }
				end
				return out
			end
		end
		-- (the nodes of its own zone; a crossing's, of both its zones (a tunnel's far side reached
		-- through the mountain); any at all when its zone has none near: a cliff at a zone's edge
		-- isn't ridden over by joining across it)
		local zones = { p.zone }
		if p.cross then zones[2] = p.into end
		local through = p.cross and (p.via == "tunnel" or p.via == "ramp")
		-- (a lift or a gate stands among the ground's nodes about it, joined to the nearest on
		-- every side: counted a change of ways in choosing, so a route passing by doesn't ride up
		-- to it and step off it as a bridge between two nodes of the ground, when that's a tie)
		local change = p.cross and (p.via == "lift" or p.via == "gate") and CHANGE_PENALTY or 0
		for k, z in ipairs(zones) do
			local r = (through and k == 2) and TUNNEL_R or (k == 1 and p.reach) or LINK_R
			local found = Near(net, p.wx, p.wy, r, LINK_K, z, true)
			if #found == 0 and #zones == 1 then found = Near(net, p.wx, p.wy, LINK_R, LINK_K, nil, true) end
			for _, near in ipairs(found) do
				local j, yd = near[1], near[2]
				local nz = net.zone[j]
				local cost = yd * PathFactor(nz) / speed + ((through and k == 2) and TUNNEL_EXTRA or 0)
				out[#out + 1] = { to = base[p.inst] + j, cost = cost, kind = "ride", link = true, pick = cost * ZoneDanger(nz) + change }
			end
		end
		return out
	end
	-- (and the network's nodes back to the places that join them)
	local backJoins = {}
	for i = 1, nSpecial do
		for _, e in ipairs(Join(i)) do
			if e.to > nSpecial then
				backJoins[e.to] = backJoins[e.to] or {}
				table.insert(backJoins[e.to], { to = i, cost = e.cost, kind = "ride", link = true, pick = e.pick, pts = e.pts })
			end
		end
	end
	-- (a city's gate: in from the city to the places that joined it)
	for z, list in pairs(gates) do
		for _, g in ipairs(list) do
			for i = 1, nSpecial do
				if i ~= g and CITY[places[i].zone] and places[i].zone == z and not places[i].cross then
					local p, q = places[i], places[g]
					if p.inst == q.inst then
						local yd = sqrt((p.wx - q.wx) ^ 2 + (p.wy - q.wy) ^ 2)
						Link(g, i, yd * PathFactor(z) / speed, "ride")
					end
				end
			end
		end
	end
	-- (two places in one city: from one to the other through its streets, not out of its gate and
	-- back in. Orgrimmar's flight master to the Valley of Spirits)
	for i = 1, nSpecial do
		local p = places[i]
		if CITY[p.zone] and not p.cross then
			for j = 1, nSpecial do
				local q = places[j]
				if j ~= i and q.zone == p.zone and not q.cross and q.inst == p.inst then
					local yd = sqrt((p.wx - q.wx) ^ 2 + (p.wy - q.wy) ^ 2)
					Link(i, j, yd * PathFactor(p.zone) / speed, "ride")
				end
			end
		end
	end

	local rideScale = NET_RIDE / speed
	local function Edges(u)
		if u <= nSpecial then
			local out = {}
			for _, e in ipairs(special[u] or {}) do out[#out + 1] = e end
			for _, e in ipairs(Join(u)) do out[#out + 1] = e end
			local p = places[u]
			if p.fm then
				for _, j in ipairs(fms) do
					if j ~= u and places[j].inst == p.inst then
						local c = FlightCost(p, places[j])
						out[#out + 1] = { to = j, cost = c, kind = "fly", pick = c + CHANGE_PENALTY }
					end
				end
			end
			return out
		end
		-- a network node: its neighbours, at your speed, counted more where it's dangerous
		local inst = (u > (base[pinst] or 0) and netOf[pinst] and u <= (base[pinst] or 0) + netOf[pinst].n) and pinst or goal.inst
		local net, off = netOf[inst], base[inst]
		local out = {}
		for _, e in ipairs(net.adj[u - off]) do
			local swimSecs = (e.swum or 0) / NET_SWIM
			local cost = max(0, e.cost - swimSecs) * rideScale + swimSecs
			out[#out + 1] = { to = off + e.to, cost = cost, kind = "ride", net = e,
				pick = cost * ZoneDanger(net.zone[e.to]) * FoeWeight(net, inst, u - off, e, foeAllow) }
		end
		for _, e in ipairs(backJoins[u] or {}) do out[#out + 1] = e end
		return out
	end

	local path, secs = Route.Search(total, Edges)
	if not path then
		if not loose then return Route.Plan(d, timeOnly, true) end
		return
	end
	if timeOnly then return nil, secs end
	-- (one ride, near enough straight: no route to show)
	local plain, swims = true, false
	for _, p in ipairs(path) do
		if p.kind ~= "ride" then plain = false end
		if p.edge.net and (p.edge.net.swum or 0) > 40 then swims = true end
		if p.edge.net and p.edge.net.drop then plain = false end   -- (a jump down on it: shown, not "straight there")
		if p.edge.pts and #p.edge.pts > 0 then plain = false end   -- (a way round on it, up a hill's one side: shown)
	end
	-- (off a pocket of ground, a mesa's top: never "straight there")
	local pnet = netOf[pinst]
	if plain and pnet and pinst == goal.inst then
		local h1, h2 = Home(pnet, px, py), Home(pnet, goal.wx, goal.wy)
		if h1 and h2 and h1 ~= h2 and not TwoWay(pnet, h1, h2) and not (pnet.inc[h1] and pnet.inc[h2]) then plain = false end
	end
	if plain and not swims and hz == goalZone then
		local straight = sqrt((px - goal.wx) ^ 2 + (py - goal.wy) ^ 2) * PathFactor(hz) / speed
		if secs <= straight * STRAIGHT_OK and secs < SHORT_RIDE then return end
	end
	local steps = Route.Steps(places, nSpecial, netOf, base, path, d)
	if Route.PickupOn() then
		local extra
		steps, extra = Route.Pickups(steps, { wx = px, wy = py, inst = pinst })
		secs = secs + extra
	end
	return steps, secs
end

-- the path as steps to read: { kind, text, to = { ui, x, y (0..100), name }, secs, via = { { ui, x, y }, ... } }
-- (via: the way there, to draw). Rides through a zone are one step; a swim, a lift, a bridge, a
-- change of zone, a flight master or a dock reached, each its own
function Route.Steps(places, nSpecial, netOf, base, path, d)
	local steps = {}
	-- where a place of the path is: its zone, world point, and (0..100) on the zone's map
	local function At(i)
		if i <= nSpecial then
			local p = places[i]
			return p.zone, p.wx, p.wy, p
		end
		for inst, net in pairs(netOf) do
			if i > base[inst] and i <= base[inst] + net.n then
				local j = i - base[inst]
				return net.zone[j], net.x[j], net.y[j], nil, net.swim[j]
			end
		end
	end
	local function MapPt(zone, wx, wy, name)
		local x, y
		if zone and zone > 0 and HBD.GetZoneCoordinatesFromWorld then x, y = HBD:GetZoneCoordinatesFromWorld(wx, wy, zone, true) end
		if not x then return end
		return { ui = zone, x = x * 100, y = y * 100, name = name }
	end
	local function Warn(text, zone)
		local lo = zone and zone > 0 and ZoneMin(zone)
		if lo and lo - (UnitLevel("player") or 1) >= WARN_FROM then
			local hi = ZoneMax(zone)
			return text .. "  |cffff6040" .. (hi and L["careful: level %d-%d"]:format(lo, hi) or L["careful: level %d+"]:format(lo)) .. "|r"
		end
		return text
	end
	-- where a way (points i..j of via) passes nearest a point: the index of the corner before it,
	-- and the point itself (a corner, or a point along a segment)
	local function Nearest(via, i, j, pt)
		local best, bestD, at = i, math.huge, via[i]
		for k = i, j do
			local a = via[k]
			local dd = (a.x - pt.x) ^ 2 + (a.y - pt.y) ^ 2
			if dd < bestD then best, bestD, at = k, dd, a end
			local b = via[k + 1]
			if b and k < j then
				local dx, dy = b.x - a.x, b.y - a.y
				local len = dx * dx + dy * dy
				if len > 0 then
					local t = ((pt.x - a.x) * dx + (pt.y - a.y) * dy) / len
					if t > 0 and t < 1 then
						local px, py = a.x + dx * t, a.y + dy * t
						local d2 = (px - pt.x) ^ 2 + (py - pt.y) ^ 2
						if d2 < bestD then best, bestD, at = k, d2, { ui = a.ui, x = px, y = py } end
					end
				end
			end
		end
		return best, at
	end
	-- a run of riding (or swimming) gathered up, then let go as one step
	local run   -- { kind ("ride"/"swim"), zone, secs, via = {}, endZone, endX, endY, endPlace }
	local function Flush(text, kind, extra)
		if not run then return end
		local to = MapPt(run.endZone, run.endX, run.endY, run.endName) or { ui = run.endZone, x = 0, y = 0 }
		-- (a jump down on the way that costs health: said, not sprung on you)
		if text and run.drop then
			text = text .. "  |cffff6040" .. L["a drop of about %d yards on the way"]:format(run.drop) .. "|r"
		end
		-- (a town of the other faction near the way: said)
		if text then
			local pts = {}
			for _, v in ipairs(run.via) do pts[#pts + 1] = v end
			pts[#pts + 1] = to
			local town = Route.FoeOnWay(pts, Route.FoeAt(d.ui, d.x, d.y))
			if town then text = text .. "  |cffff6040" .. L["careful: passes %s"]:format(town) .. "|r" end
		end
		local s = { kind = kind or run.kind, text = text, to = to, secs = run.secs, via = run.via, rideZone = run.zone, drop = run.drop }
		for k, v in pairs(extra or {}) do s[k] = v end
		steps[#steps + 1] = s
		run = nil
	end
	for i, p in ipairs(path) do
		local az, ax, ay, ap = At(p.from)
		local bz, bx, by, bp, bswim = At(p.to)
		local nextKind = path[i + 1] and path[i + 1].kind
		if p.kind == "ride" then
			local e = p.edge
			-- (from a crossing on into the zone it leads to: the crossing's own step said so)
			if ap and ap.cross and ap.into == bz then az = bz end
			local swim = e.net and (e.net.swum or 0) > 0 and (e.net.swum / NET_SWIM) > e.cost * 0.5
			local kind = swim and "swim" or "ride"
			-- (a new run: a change of mode (riding, swimming); the step so far let go first. A
			-- change of zone doesn't end the run: the ride on into the next zone is one step)
			if run and run.kind ~= kind then
				if run.kind == "swim" then
					Flush(L["Swim to %s"]:format(PlaceName(run.endZone, run.endX and run.endMapX or 0, run.endMapY or 0)), "swim")
				else
					Flush(Warn(L["Go to %s"]:format(PlaceName(run.endZone, run.endMapX or 0, run.endMapY or 0)), run.zone), "ride")
				end
			end
			if not run then run = { kind = kind, zone = bz ~= 0 and bz or az, from = az, secs = 0, via = {}, fromStart = ap and ap.start and { ap.wx, ap.wy } } end
			if e.net and e.net.drop then run.drop = max(run.drop or 0, e.net.drop) end
			-- (the way: the edge's points between, a to b, or b to a; then the node it ends at)
			local edgeAt = #run.via
			if e.net and e.net.mids then
				local m = Mids(e.net)
				if e.net.fwd then
					for k = 1, #m, 2 do local pt = MapPt(run.zone, m[k], m[k + 1]) if pt then run.via[#run.via + 1] = pt end end
				else
					for k = #m - 1, 1, -2 do local pt = MapPt(run.zone, m[k], m[k + 1]) if pt then run.via[#run.via + 1] = pt end end
				end
			end
			-- (a way round, to where you're going or from where you are: its points)
			if e.pts and #e.pts > 0 then
				for _, w in ipairs(e.pts) do
					local pt = MapPt(run.zone, w[1], w[2])
					if pt then run.via[#run.via + 1] = pt end
				end
				run.fromStart = nil
			end
			-- (a way's end too: the line's drawn through it, along the way)
			if not bp or bp.way then
				local pt = MapPt(run.zone, bx, by)
				if pt then run.via[#run.via + 1] = pt end
			end
			-- (the first way out from you: from where it passes nearest you, not from its far end
			-- and back. You joined a node near you; the way on from it may run right past you)
			if run.fromStart and #run.via > 1 then
				local me = MapPt(run.zone, run.fromStart[1], run.fromStart[2])
				run.fromStart = nil
				if me then
					local best, at = Nearest(run.via, 1, #run.via, me)
					local kept = { at }
					for k = best + 1, #run.via do kept[#kept + 1] = run.via[k] end
					run.via = kept
				end
			end
			-- (the last way in to the goal: cut where it passes nearest the goal. The goal joined a
			-- node near it, maybe one past it, up Zul'Gurub's stairs and in: the way needn't go on
			-- past the gate and come back)
			if bp and bp.goal and #run.via > 1 and not (e.pts and #e.pts > 0) then
				local g = MapPt(run.zone, bx, by)
				if g then
					local best, at = Nearest(run.via, math.max(1, #run.via - 4), #run.via, g)
					for k = #run.via, best + 1, -1 do run.via[k] = nil end
					if at ~= run.via[best] then run.via[#run.via + 1] = at end
				end
			end
			run.secs = run.secs + p.cost
			run.endZone, run.endX, run.endY, run.endName = (bz ~= 0 and bz or run.zone), bx, by, bp and bp.name
			local mp = MapPt(run.endZone, bx, by)
			run.endMapX, run.endMapY = mp and mp.x / 100 or 0, mp and mp.y / 100 or 0
			if bz ~= az and bz ~= 0 and az ~= 0 and not (bp and (bp.goal or bp.cross)) then
				-- (into another zone: said so, the step ending at its first node there)
				local extra = { zoneTo = bz }
				if run.kind == "swim" then
					Flush(L["Swim to %s"]:format(ns.ZoneName(bz) or "?"), "swim", extra)
				else
					Flush(Warn(L["Go into %s"]:format(ns.ZoneName(bz) or "?"), run.zone), "exit", extra)
				end
			end
			-- (a place reached: the step ends there, named for what's next)
			if bp then
				local mpt = bp.x and bp.y
				if bp.goal then
					Flush(Warn(L["Go to %s"]:format(d.name), run.zone), run.kind)
				elseif bp.fm and nextKind == "fly" then
					Flush((bp.fresh and L["Pick up the flight path: %s"] or L["Go to the flight master: %s"]):format(bp.name), run.kind)
				elseif bp.dock and nextKind == "transport" then
					local leg = path[i + 1].leg
					Flush((GO_TO[leg[7]] or GO_TO.boat):format(PlaceName(leg[4], leg[5] / 100, leg[6] / 100)), run.kind)
				elseif bp.cross and nextKind == "cross" then
					-- (a bridge or tunnel ahead: the step ends at its near end, the crossing its own)
					local kind = path[i + 1].leg
					if kind then Flush(Warn(L["Go to %s"]:format(PlaceName(bp.ui, bp.x, bp.y)), run.zone), run.kind) end
				elseif bp.cross then
					-- (a lift, gate, tunnel or ramp: one point in both zones. The step there, then "take the lift into":
					-- out of the city when the ride began in it, from Undercity up to Tirisfal)
					local into = bp.into ~= (run.from or run.zone) and bp.into or bp.zone
					local tz = into
					Flush(Warn(L["Go to %s"]:format(PlaceName(bp.ui, bp.x, bp.y)), run.zone), run.kind)
					local to = MapPt(tz, bx, by) or MapPt(bp.zone, bx, by) or { ui = bp.zone, x = bp.x * 100, y = bp.y * 100 }
					if nextKind == "ride" then
						steps[#steps + 1] = { kind = "exit", text = (CROSS_TEXT[bp.via] or L["Go into %s"]):format(ns.ZoneName(into) or "?"),
							to = to, secs = 5, zoneTo = into }
					end
				end
			end
		elseif p.kind == "cross" then
			Flush(Warn(L["Go to %s"]:format(PlaceName(ap.ui, ap.x, ap.y)), run and run.zone), run and run.kind)
			local to = MapPt(bz, bx, by, bp and bp.name) or { ui = bz, x = bp.x * 100, y = bp.y * 100 }
			steps[#steps + 1] = { kind = "exit", text = (CROSS_TEXT[p.leg] or L["Go into %s"]):format(ns.ZoneName(bz) or "?"),
				to = to, secs = p.cost, zoneTo = bz }
		elseif p.kind == "fly" then
			Flush((ap.fresh and L["Pick up the flight path: %s"] or L["Go to the flight master: %s"]):format(ap.name), run and run.kind)
			steps[#steps + 1] = { kind = "fly", text = L["Fly to %s"]:format(bp.name), to = MapPt(bz, bx, by, bp.name), secs = p.cost }
		elseif p.kind == "transport" then
			local leg = p.leg
			Flush((GO_TO[leg[7]] or GO_TO.boat):format(PlaceName(leg[4], leg[5] / 100, leg[6] / 100)), run and run.kind)
			local where = PlaceName(leg[4], leg[5] / 100, leg[6] / 100)
			steps[#steps + 1] = { kind = "transport", text = (TAKE[leg[7]] or TAKE.boat):format(where),
				to = MapPt(bz, bx, by, where), secs = p.cost, transport = leg[7] }
		elseif p.kind == "hearth" then
			Flush(nil, run and run.kind)
			steps[#steps + 1] = { kind = "hearth", text = L["Use your Hearthstone (%s)"]:format(bp.name), to = MapPt(bz, bx, by, bp.name), secs = p.cost }
		end
	end
	Flush(L["Go to %s"]:format(d.name), run and run.kind)
	-- (a step with no words: an oddity; the one after it tells the way)
	local out = {}
	for _, s in ipairs(steps) do if s.text then out[#out + 1] = s end end
	return out
end

--- whether a route picks up the flight paths you don't have on the way (the route's own box)
function Route.PickupOn()
	local r = Store()
	return r and r.pickup == true
end

--- steps with stops added at the flight paths you don't have yet that are near a ride (the
--- same zone, a short way off it): the steps, and the seconds the stops add
function Route.Pickups(steps, from)
	local missing = {}
	for _, f in ipairs(FlightNodes()) do
		if OursFlight(f) and not Known(f) then missing[#missing + 1] = f end
	end
	if #missing == 0 then return steps, 0 end
	local speed = GroundSpeed()
	local out, extra, taken = {}, 0, {}
	local ax, ay, ainst = from.wx, from.wy, from.inst
	for _, s in ipairs(steps) do
		local bx, by, binst = World(s.to.ui, s.to.x / 100, s.to.y / 100)
		if (s.kind == "ride" or s.kind == "exit") and ax and bx and ainst == binst then
			-- (each one in this ride's zone that going by adds little riding, in the order you'd
			-- come to them: one after another, each from the last)
			local zone = s.rideZone or ZoneOf(s.to.ui)
			local function D(x1, y1, x2, y2) return sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end
			local direct = D(ax, ay, bx, by)
			local allow = max(PICKUP_DETOUR, direct * PICKUP_SHARE)
			local near = {}
			for _, f in ipairs(missing) do
				if not taken[f] and f.inst == binst and f.ui == zone then
					local detour = D(ax, ay, f.wx, f.wy) + D(f.wx, f.wy, bx, by) - direct
					if detour <= allow then near[#near + 1] = { f = f, along = D(ax, ay, f.wx, f.wy) } end
				end
			end
			table.sort(near, function(x, y) return x.along < y.along end)
			local cx, cy = ax, ay
			for _, n in ipairs(near) do
				local f = n.f
				taken[f] = true
				local added = D(cx, cy, f.wx, f.wy) + D(f.wx, f.wy, bx, by) - D(cx, cy, bx, by)
				local secs = max(0, added) * GROUND_DETOUR / speed + 10
				extra = extra + secs
				out[#out + 1] = { kind = "pickup", text = L["Pick up the flight path: %s"]:format(f.name),
					to = { ui = f.ui, x = f.x * 100, y = f.y * 100, name = f.name }, secs = secs }
				cx, cy = f.wx, f.wy
			end
			-- (stopped on the way: the ride's way from the last stop, the points still ahead of
			-- it, nearer its end than the stop is. Not back to where it began)
			if #near > 0 and s.via then
				local left = D(cx, cy, bx, by)
				local via = {}
				for _, v in ipairs(s.via) do
					local vx, vy = World(v.ui, v.x / 100, v.y / 100)
					if vx and D(vx, vy, bx, by) < left then via[#via + 1] = v end
				end
				local copy = {}
				for k, v in pairs(s) do copy[k] = v end
				copy.via = #via > 0 and via or nil
				s = copy
			end
		end
		out[#out + 1] = s
		ax, ay, ainst = bx, by, binst
	end
	return out, extra
end

--------------------------------------------------------------------------------
-- Learning as you play: the flight paths a flight master's map shows you know; how long each
-- flight takes; how fast your mount is
--------------------------------------------------------------------------------

local flying   -- { from, to, start, onTaxi }

local function CurrentNode()
	for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
		if TaxiNodeGetType(i) == "CURRENT" then return TaxiNodeName(i) end
	end
end

--------------------------------------------------------------------------------
-- A route's flight, on the flight master's map: the place to click pulsing purple, "Fly here"
-- just over it, until the map closes
--------------------------------------------------------------------------------

local taxiMark
local GLOW_SIZE = 1.9          -- the glow: this many times the flight path's icon
local PULSE_SECS = 1.2         -- one pulse of the glow (and of "Fly here"): a smooth wave
local PULSE_COLOUR = { 0.78, 0.35, 1 }   -- a vivid purple: stands out on the flight map's gold and brown

-- the icon a flight path's button shows (its own texture, or atlas), to glow in its shape
local function CopyIcon(dst, button)
	local src = button.GetNormalTexture and button:GetNormalTexture()
	local atlas = src and src.GetAtlas and src:GetAtlas()
	if atlas and dst.SetAtlas then
		dst:SetAtlas(atlas)
		return
	end
	local tex = src and src:GetTexture()
	dst:SetTexture(tex or "Interface\\TaxiFrame\\UI-Taxi-Icon-White")
	if src and src.GetTexCoord then dst:SetTexCoord(src:GetTexCoord()) end
end

local function MarkTaxi(button)
	if not taxiMark then
		local f = CreateFrame("Frame", nil, UIParent)
		f:SetFrameStrata("DIALOG")
		f:EnableMouse(false)
		-- (the icon itself again, larger and brighter, added on: its own shape glowing; twice over,
		-- for a stronger colour)
		local function Glow()
			local g = f:CreateTexture(nil, "OVERLAY")
			g:SetBlendMode("ADD")
			g:SetVertexColor(PULSE_COLOUR[1], PULSE_COLOUR[2], PULSE_COLOUR[3])
			g:SetPoint("CENTER")
			return g
		end
		f.glow, f.glowCore, f.glow2 = Glow(), Glow(), Glow()
		-- ("Fly here" just over the flight path, pulsing with it)
		local text = ns.Text(f, "GameFontNormal")
		text:SetPoint("BOTTOM", f, "TOP", 0, 4)
		ns.Outline(text, 13)
		text:SetTextColor(PULSE_COLOUR[1], PULSE_COLOUR[2], PULSE_COLOUR[3])
		text:SetText(L["Fly here"])
		f.text = text
		-- (all on one smooth wave: no seam where an animation would start over)
		local t = 0
		f:SetScript("OnUpdate", function(self, elapsed)
			t = (t + elapsed) % PULSE_SECS
			local wave = (1 - math.cos(t / PULSE_SECS * 2 * math.pi)) / 2   -- 0 .. 1 .. 0
			self.glow:SetAlpha(0.45 + 0.55 * wave)
			self.glowCore:SetAlpha(0.3 + 0.7 * wave)
			self.glow2:SetAlpha(0.7 * (1 - wave))
			local s = self.size or 16
			self.glow2:SetSize(s * (GLOW_SIZE + 0.7 * wave), s * (GLOW_SIZE + 0.7 * wave))
			self.text:SetAlpha(0.55 + 0.45 * wave)
		end)
		taxiMark = f
	end
	local f = taxiMark
	local w, h = button:GetSize()
	f.size = math.max(w or 16, h or 16)
	f:SetParent(button)
	f:SetFrameStrata("DIALOG")
	f:ClearAllPoints()
	f:SetPoint("CENTER", button, "CENTER")
	f:SetSize(f.size, f.size)
	CopyIcon(f.glow, button)
	CopyIcon(f.glowCore, button)
	CopyIcon(f.glow2, button)
	f.glow:SetSize(f.size * GLOW_SIZE, f.size * GLOW_SIZE)
	f.glowCore:SetSize(f.size * 1.3, f.size * 1.3)
	f:Show()
end

local function UnmarkTaxi()
	if taxiMark then taxiMark:Hide() end
end

-- the flight a route has you take next: its destination's button on the flight master's map
-- a flight path you can fly to from this flight master now
local function Reachable(t) return t == "REACHABLE" end

local function ShowRouteFlight(again)
	UnmarkTaxi()
	if not route then return end
	local dest
	for i = route.at, #route.steps do
		local s = route.steps[i]
		if s.kind == "fly" then dest = s.to.name break end
		if s.kind ~= "ride" and s.kind ~= "exit" and s.kind ~= "swim" and s.kind ~= "pickup" then break end   -- (a boat or the like first: not this flight master's)
	end
	if not dest then return end
	for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
		if TaxiNodeName(i) == dest and Reachable(TaxiNodeGetType(i)) then
			local button = _G["TaxiButton" .. i]
			if button and button:IsVisible() then
				MarkTaxi(button)
			else
				ns.Print(L["Fly to %s"]:format(dest))
			end
			return
		end
	end
	-- (not a flight you can take from here: planned before your flight paths here were known.
	-- Known now: the way again, from here)
	if not again and route.goal then
		ns.Print(L["You can't fly to %s from here yet: finding another way."]:format(dest))
		Route.Start(route.goal)
		ShowRouteFlight(true)
	end
end

local learn = CreateFrame("Frame")
learn:RegisterEvent("TAXIMAP_OPENED")
learn:RegisterEvent("TAXIMAP_CLOSED")
learn:SetScript("OnEvent", function(_, event)
	if event == "TAXIMAP_CLOSED" then UnmarkTaxi() return end
	-- (after the game's own map has set out its buttons)
	C_Timer.After(0, ShowRouteFlight)
	local r = Store()
	if not r then return end
	-- (the continent: the world you're in, as the flight paths' places are worked out)
	local inst = HBD and HBD.GetPlayerWorldPosition and select(3, HBD:GetPlayerWorldPosition())
	if not inst then return end
	r.learned[Me()] = r.learned[Me()] or {}
	-- (what this flight master's map shows is all of it: the list made again, not added to)
	local set = {}
	for i = 1, NumTaxiNodes() do
		local t = TaxiNodeGetType(i)
		if t == "CURRENT" or t == "REACHABLE" then set[TaxiNodeName(i)] = true end
	end
	r.learned[Me()][inst] = set
end)

if hooksecurefunc and TakeTaxiNode then
	hooksecurefunc("TakeTaxiNode", function(i)
		local from, to = CurrentNode(), TaxiNodeName(i)
		if from and to then flying = { from = from, to = to, start = GetTime() } end
	end)
end

local watch = CreateFrame("Frame")
local since = 0
watch:SetScript("OnUpdate", function(_, elapsed)
	since = since + elapsed
	if since < 1 then return end
	since = 0
	local r = Store()
	if not r then return end
	-- a flight timed: from when it was taken until you're off the taxi
	if flying then
		local on = UnitOnTaxi("player")
		if on then
			flying.onTaxi = true
		elseif flying.onTaxi then
			local secs = GetTime() - flying.start
			if secs > 5 then r.flights[flying.from .. "|" .. flying.to] = floor(secs + 0.5) end
			flying = nil
		elseif GetTime() - flying.start > 10 then
			flying = nil   -- (never took off)
		end
	end
	-- (the other faction's towns: found once Questie's data is read, here, not on the click
	-- that plans the first route)
	if not foes and ns.Index and ns.Index.done then Foes(0) end
	-- your mount's speed, the fastest seen
	if IsMounted and IsMounted() and not UnitOnTaxi("player") then
		-- (in a fight the game keeps your speed secret: a number that can't be compared. Left be)
		pcall(function()
			local _, run = GetUnitSpeed("player")
			if _G.issecretvalue and issecretvalue(run) then return end
			if type(run) == "number" and run > (r.speed[Me()] or 0) and run < 30 then r.speed[Me()] = run end
		end)
	end
end)

--------------------------------------------------------------------------------
-- Following a route: the steps on the map, an arrow to the one you're on, on to the next as
-- you get there
--------------------------------------------------------------------------------

-- (route: declared at the top)
local panel, rows = nil, {}
local ticker
local ROW = 18
local KIND_ICON = {
	ride = "Interface\\Icons\\Ability_Mount_RidingHorse",
	fly = "Interface\\Icons\\Ability_Hunter_EagleEye",
	transport = "Interface\\Icons\\INV_Misc_Map_01",
	hearth = "Interface\\Icons\\INV_Misc_Rune_01",
}
KIND_ICON.pickup = KIND_ICON.fly
KIND_ICON.swim = "Interface\\Icons\\Spell_Shadow_DemonBreath"
KIND_ICON.exit = KIND_ICON.ride
KIND_ICON.farm = "Interface\\Icons\\Trade_Mining"
local LOOP_ROWS = 5   -- a farming loop's panel: the next few spots
local TRANSPORT_ICON = { boat = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",
	zeppelin = "Interface\\Icons\\INV_Misc_Bomb_04", tram = "Interface\\Icons\\INV_Misc_Gear_01",
	portal = "Interface\\Icons\\Spell_Arcane_PortalStormWind", skycutter = "Interface\\Icons\\Ability_Hunter_EagleEye",
	swim = "Interface\\Icons\\Spell_Shadow_DemonBreath", lift = "Interface\\Icons\\INV_Misc_Gear_01" }

local function Minutes(secs)
	local m = floor((secs or 0) / 60 + 0.5)
	if m < 1 then return L["under a minute"] end
	return L["%d min"]:format(m)
end
Route.Minutes = Minutes

local function Distance(to)
	if not (HBD and HBD.GetPlayerWorldPosition) then return end
	local px, py, pi = HBD:GetPlayerWorldPosition()
	local wx, wy, wi = World(to.ui, to.x / 100, to.y / 100)
	if not (px and wx) or pi ~= wi then return end
	return sqrt((px - wx) ^ 2 + (py - wy) ^ 2)
end

-- the route on the minimap: the ground still to cover, pink (a flight, a boat or the hearthstone
-- breaks it: no line over the sea); a farming loop, green and closed. Drawn under the minimap's
-- own icons, the herbs and veins it tracks
local MINI_RIDE, MINI_FARM = { 0.98, 0.59, 1, 0.95 }, { 0.35, 1, 0.45, 0.9 }
local MINI_NOW = { 1, 1, 1, 0.95 }   -- (the step you're on: white, as on the world map)
local NOT_GROUND = { fly = true, transport = true, hearth = true }
local function UpdateMini()
	local P = ns.Pins
	if not (P and P.SetMiniPaths) then return end
	if not route or (ns.db and ns.db.miniRoute == false) then P.SetMiniPaths(nil) return end
	local paths = {}
	local function Ring(steps)
		local pts = {}
		for _, s in ipairs(steps) do
			for _, v in ipairs(s.via or {}) do pts[#pts + 1] = v end
			pts[#pts + 1] = s.to
		end
		paths[#paths + 1] = { pts = pts, closed = true, col = MINI_FARM }
	end
	if route.loop then
		Ring(route.steps)
	else
		-- (the step you're on, over ground: its line starts at you, as the world map's does. you:
		-- how many of the path's first points are that step's)
		local cur, you = {}, nil
		for i = route.at, #route.steps do
			local s = route.steps[i]
			if NOT_GROUND[s.kind] then
				if #cur > 1 or you then paths[#paths + 1] = { pts = cur, col = MINI_RIDE, you = you, now = MINI_NOW } end
				cur, you = { s.to }, nil
			else
				for _, v in ipairs(s.via or {}) do cur[#cur + 1] = v end
				cur[#cur + 1] = s.to
				if i == route.at then you = #cur end
			end
		end
		if #cur > 1 or you then paths[#paths + 1] = { pts = cur, col = MINI_RIDE, you = you, now = MINI_NOW } end
		if route.after and route.after.steps then Ring(route.after.steps) end
	end
	P.SetMiniPaths(paths)
end

--- the setting for it changed: drawn again, or taken off
function Route.UpdateMini() UpdateMini() end

local function Refresh()
	UpdateMini()
	if not panel then return end
	if not route then panel:Hide() return end
	local loop = route.loop
	if loop then
		panel.title:SetText(L["Farming %s: about %s a lap (lap %d)"]:format(route.dest, Minutes(route.total), route.lap or 1))
	else
		panel.title:SetText(L["Route to %s: about %s"]:format(route.dest, Minutes(route.total)))
	end
	local w = panel.title:GetStringWidth() + 60
	-- (the steps shown: all of a route's; a loop's next few, round past its end)
	local show = {}
	if loop then
		local n = #route.steps
		for k = 0, min(LOOP_ROWS, n) - 1 do show[#show + 1] = (route.at - 1 + k) % n + 1 end
	else
		for i = 1, #route.steps do show[i] = i end
	end
	for row, i in ipairs(show) do
		local s = route.steps[i]
		local r = rows[row]
		if not r then
			r = CreateFrame("Frame", nil, panel)
			r:SetHeight(ROW)
			r.icon = r:CreateTexture(nil, "ARTWORK")
			r.icon:SetSize(14, 14)
			r.icon:SetPoint("LEFT", 6, 0)
			r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			r.text = ns.Text(r, "GameFontHighlightSmall")
			r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
			if ns.SkinText then ns.SkinText(r.text) end
			rows[row] = r
		end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -22 - (row - 1) * ROW)
		r:SetPoint("RIGHT", panel, "RIGHT")
		r.icon:SetTexture(s.icon or (s.transport and TRANSPORT_ICON[s.transport]) or KIND_ICON[s.kind])
		r.text:SetText(("%d. %s  |cff999999(%s)|r"):format(i, s.text, Minutes(s.secs)))
		if i < route.at and not loop then
			r.text:SetTextColor(0.5, 0.5, 0.5)
			r.icon:SetDesaturated(true)
		elseif i == route.at then
			r.text:SetTextColor(1, 0.82, 0.1)
			r.icon:SetDesaturated(false)
		else
			r.text:SetTextColor(1, 1, 1)
			r.icon:SetDesaturated(false)
		end
		w = max(w, r.text:GetStringWidth() + 36)
		r:Show()
	end
	for i = #show + 1, #rows do rows[i]:Hide() end
	-- (picking up flight paths: not on a loop)
	panel.pickup:SetShown(not loop)
	panel.pickupText:SetShown(not loop)
	panel.pickup:SetChecked(Route.PickupOn())
	if not loop then w = max(w, panel.pickupText:GetStringWidth() + 40) end
	panel:SetSize(min(w, 460), 28 + #show * ROW + (loop and 6 or 30))
	panel:Show()
end

-- the panel where it's to be: on the map, at its foot; or popped out (ns.db.routeOut), a window
-- of its own on the screen, dragged where you like and kept there (ns.db.routePos), up with the
-- map closed. false when it's to be on the map and the map's not been made yet
local function Place(p)
	local out = ns.db and ns.db.routeOut
	local layer = ns.Pins.Layer and ns.Pins.Layer()
	if not out and not layer then return false end
	p:ClearAllPoints()
	if out then
		p:SetParent(UIParent)
		p:SetFrameStrata("MEDIUM")
		p:SetClampedToScreen(true)
		p:SetMovable(true)
		local at = ns.db.routePos
		if type(at) == "table" and at[1] then
			p:SetPoint(at[1], UIParent, at[1], at[2] or 0, at[3] or 0)
		else
			p:SetPoint("LEFT", UIParent, "LEFT", 40, 0)
		end
	else
		p:SetParent(layer)
		p:SetFrameStrata(layer:GetFrameStrata())
		p:SetFrameLevel(layer:GetFrameLevel() + 30)
		p:SetClampedToScreen(false)
		p:SetMovable(false)
		p:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 10, 40)
	end
	if p.out then
		p.out.tex:SetTexture(out and "Interface\\Buttons\\UI-Panel-CollapseButton-Up" or "Interface\\Buttons\\UI-Panel-ExpandButton-Up")
	end
	return true
end

local function MakePanel()
	if panel then return panel end
	local parent = ns.Pins.Layer and ns.Pins.Layer()
	-- (popped out: it needs no map)
	if not parent and not (ns.db and ns.db.routeOut) then return end
	local p = CreateFrame("Frame", nil, parent or UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	if p.SetBackdrop then
		p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		p:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
		p:SetBackdropBorderColor(1, 0.82, 0.1, 0.8)
	end
	p:EnableMouse(true)
	-- (EUI: its flat panel in place of the dark one and its gold edge)
	if ns.SkinPanel then ns.SkinPanel(p) end
	-- (at its foot: pick up flight paths on the way; ticked or cleared, the route's planned again)
	local box = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
	box:SetSize(22, 22)
	box:SetPoint("BOTTOMLEFT", 4, 3)
	if ns.OnSkin then ns.OnSkin(function(S) if S.Checkbox then pcall(S.Checkbox, box) end end) end
	local boxText = ns.Text(p, "GameFontHighlightSmall")
	boxText:SetPoint("LEFT", box, "RIGHT", 2, 0)
	boxText:SetText(L["Pick up flight paths on the way"])
	if ns.SkinText then ns.SkinText(boxText) end
	box:SetScript("OnClick", function(self)
		local r = Store()
		if r then r.pickup = self:GetChecked() and true or false end
		Route.Recalculate()
	end)
	box:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Pick up flight paths on the way"], 1, 0.82, 0.1)
		GameTooltip:AddLine(L["Stops at the flight masters near the route whose flight paths you don't have yet, for quicker travel later."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	box:SetScript("OnLeave", function() GameTooltip:Hide() end)
	p.pickup, p.pickupText = box, boxText
	local title = ns.Text(p, "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", 8, -6)
	if ns.SkinText then ns.SkinText(title) end
	p.title = title
	local x = CreateFrame("Button", nil, p)
	x:SetSize(14, 14)
	x:SetPoint("TOPRIGHT", -4, -4)
	local xt = x:CreateTexture(nil, "ARTWORK")
	xt:SetAllPoints()
	xt:SetTexture("Interface\\Buttons\\UI-StopButton")
	xt:SetAlpha(0.7)
	x:SetScript("OnEnter", function(self)
		xt:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(route and (route.loop or route.after) and L["Stop farming"] or L["Stop following this route"], 1, 1, 1)
		GameTooltip:Show()
	end)
	x:SetScript("OnLeave", function() xt:SetAlpha(0.7) GameTooltip:Hide() end)
	x:SetScript("OnClick", function() Route.Stop() end)
	if ns.SkinClose then ns.SkinClose(x, xt) end
	-- (beside it: out of the map into a window of its own, and back)
	local o = CreateFrame("Button", nil, p)
	o:SetSize(16, 16)
	o:SetPoint("RIGHT", x, "LEFT", -3, 0)
	local ot = o:CreateTexture(nil, "ARTWORK")
	ot:SetAllPoints()
	ot:SetAlpha(0.7)
	o.tex = ot
	o:SetScript("OnEnter", function(self)
		ot:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if ns.db.routeOut then
			GameTooltip:AddLine(L["Put the route back on the map"], 1, 1, 1)
		else
			GameTooltip:AddLine(L["Open the route outside the map"], 1, 1, 1)
			GameTooltip:AddLine(L["It stays up with the map closed. Drag it where you like."], 0.7, 0.7, 0.7, true)
		end
		GameTooltip:Show()
	end)
	o:SetScript("OnLeave", function() ot:SetAlpha(0.7) GameTooltip:Hide() end)
	o:SetScript("OnClick", function()
		GameTooltip:Hide()
		ns.db.routeOut = not ns.db.routeOut or nil
		-- (back on a map that's never been opened: it has nowhere to go yet, and waits for it)
		if not Place(p) then p:Hide() return end
		Refresh()
	end)
	p.out = o
	-- (popped out: dragged by its body, and where it's left kept)
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnDragStart", function(self) if ns.db.routeOut and self:IsMovable() then self:StartMoving() end end)
	p:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if not ns.db.routeOut then return end
		local point, _, _, px, py = self:GetPoint(1)
		if point then ns.db.routePos = { point, px, py } end
		-- (as the game left it: by a corner of the screen. Set again by ours, to stay put)
		Place(self)
	end)
	Place(p)
	p:Hide()
	panel = p
	return p
end

local waypoint   -- (TomTom's, to take off when the step's done)
local ownPinUntil = 0   -- (the game's map pin set by a route itself, until then: not a new pin of yours)
local function PointAt(step)
	if waypoint and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, waypoint) end
	ownPinUntil = GetTime() + 1
	waypoint = ns.Pins.SetWaypoint({ ui = step.to.ui, x = step.to.x, y = step.to.y, name = step.text }, true)
end

local function Say(text) ns.Print(text) end

local DrawLine   -- (the route on the map: below)

-- the route kept (per character) so a reload or a log out picks it up where it was; or let go
local function Save()
	local r = Store()
	if not r then return end
	r.active = r.active or {}
	r.active[Me()] = route and { steps = route.steps, at = route.at, total = route.total, dest = route.dest,
		goal = route.goal, loop = route.loop, lap = route.lap, after = route.after } or nil
end

local function Go(i)
	-- (a farming loop's end: round again, from its first spot)
	if route.loop and not route.steps[i] then
		i = 1
		route.lap = (route.lap or 1) + 1
		Say(L["Lap %d of %s"]:format(route.lap, route.dest))
	end
	route.at = i
	Save()
	local s = route.steps[i]
	if not s then
		-- (the way to a farming loop done: round the loop now)
		if route.after then
			local loop = route.after
			loop.direct = true
			Route.StartLoop(loop)
			return
		end
		Say(L["You've arrived: %s"]:format(route.dest))
		Route.Stop()
		return
	end
	PointAt(s)
	if not route.loop then Say(L["Next: %s"]:format(s.text)) end   -- (a loop's spots: too many to say each)
	Refresh()
end

-- off the route: further than this from the step you're on (a ride's way; a flight's or a boat's
-- start), for a few seconds: it's planned again from where you are, no more often than this. (On
-- a flight, a boat, or the hearthstone being cast: left be)
local OFF_ROUTE = 350          -- yards
local OFF_AGAIN = 20           -- seconds
local offSince, lastPlan = nil, -math.huge

local function SegDist(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local l2 = dx * dx + dy * dy
	local t = l2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) or 0
	return sqrt((px - ax - t * dx) ^ 2 + (py - ay - t * dy) ^ 2)
end

local function OffRoute()
	if not (route and route.goal) or route.loop then return false end
	local s = route.steps[route.at]
	if not s or s.kind == "transport" or s.kind == "hearth" then return false end
	if not (HBD and HBD.GetPlayerWorldPosition) then return false end
	local px, py, pinst = HBD:GetPlayerWorldPosition()
	if not px then return false end
	-- the step you're on: from where it begins (the step before's end, or where the route
	-- began), by its way, to its end. A ride's: along it. A flight's: at its start (the flight
	-- master), its end's a flight away
	local ax, ay, ainst
	local prev = route.steps[route.at - 1]
	if prev then ax, ay, ainst = World(prev.to.ui, prev.to.x / 100, prev.to.y / 100)
	elseif route.from then ax, ay, ainst = route.from[1], route.from[2], route.from[3] end
	if not ax then return false end
	local best = ainst == pinst and sqrt((px - ax) ^ 2 + (py - ay) ^ 2) or math.huge
	if not NOT_GROUND[s.kind] then
		local pts = {}
		for _, v in ipairs(s.via or {}) do pts[#pts + 1] = v end
		pts[#pts + 1] = s.to
		for _, p in ipairs(pts) do
			local bx, by, binst = World(p.ui, p.x / 100, p.y / 100)
			if bx and binst == pinst and ainst == pinst then
				best = math.min(best, SegDist(px, py, ax, ay, bx, by))
			elseif bx and binst == pinst then
				best = math.min(best, sqrt((px - bx) ^ 2 + (py - by) ^ 2))
			end
			ax, ay, ainst = bx, by, binst
		end
	end
	return best > OFF_ROUTE
end

local PASSABLE = { farm = true, ride = true, swim = true }   -- steps that may be gone by
local PASS_NEAR = 150    -- yards: past a spot within this of it, it's passed
local PASS_GAIN = 25     -- yards nearer the next spot than the spot itself is: passed, however far off
local PASS_SECS = 2      -- for this long (not a swerve round a tree)
local passedSince
local function Check()
	if not route then return end
	local s = route.steps[route.at]
	if not s then return end
	if UnitOnTaxi("player") then return end
	local here = ns.PlayerMap and ns.PlayerMap()
	local zone = here and ZoneOf(here)
	-- (a later step already reached: on to the one after it)
	-- (round a farming loop: only the next few spots. Its last spot is where a lap ends: stood
	-- at it with the first spot next, it isn't "a later step reached" again, a lap every tick)
	local last = #route.steps
	if route.loop then last = math.min(last, route.at + (#route.steps > 6 and 3 or 0)) end
	for j = last, route.at, -1 do
		local t = route.steps[j]
		local d = Distance(t.to)
		local there = (d and d <= (ARRIVE[t.kind] or 30)) or (t.zoneTo and zone == t.zoneTo and j == route.at)
		if there and not (t.kind == "fly" and UnitOnTaxi("player")) then
			Go(j + 1)
			return
		end
	end
	-- (gone by it without coming near enough: a spot of a farming loop, the end of a ride with
	-- another ride after it. Past it towards the next one, or nearer the next one than it is: on
	-- to the next, not an arrow pointing back the way you came. Not a flight master, a dock or a
	-- lift, which you do have to reach)
	local n = #route.steps
	local nxt = route.steps[route.at + 1] or (route.loop and n > 1 and route.steps[1]) or nil
	if nxt and PASSABLE[s.kind] and PASSABLE[nxt.kind] and HBD and HBD.GetPlayerWorldPosition then
		local px, py, pinst = HBD:GetPlayerWorldPosition()
		local bx, by, binst = World(s.to.ui, s.to.x / 100, s.to.y / 100)
		local cx, cy, cinst = World(nxt.to.ui, nxt.to.x / 100, nxt.to.y / 100)
		if px and bx and cx and pinst == binst and binst == cinst then
			local toNext = sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
			local fromHere = sqrt((px - bx) ^ 2 + (py - by) ^ 2)
			local hop = sqrt((cx - bx) ^ 2 + (cy - by) ^ 2)
			-- (beyond it, on the next one's side of it, and not far off; or nearer the next than it is)
			local beyond = (px - bx) * (cx - bx) + (py - by) * (cy - by) > 0
			if (beyond and fromHere <= PASS_NEAR and fromHere > (ARRIVE[s.kind] or 30)) or (toNext + PASS_GAIN < hop and toNext < fromHere) then
				passedSince = passedSince or GetTime()
				if GetTime() - passedSince >= PASS_SECS then
					passedSince = nil
					Go(route.at + 1)
					return
				end
			else
				passedSince = nil
			end
		end
	else
		passedSince = nil
	end
	-- (off it a moment, not just round a tree: the way from here)
	if OffRoute() then
		offSince = offSince or GetTime()
		if GetTime() - offSince >= 3 and GetTime() - lastPlan >= OFF_AGAIN then
			offSince, lastPlan = nil, GetTime()
			Route.Recalculate()
		end
	else
		offSince = nil
	end
end

--- plan the way to d and follow it: true when there's a route (more than riding straight there)
function Route.Start(d)
	-- (your flight paths here not known yet: said, once a session for each continent, so a route
	-- with no flights in it isn't a puzzle)
	if HBD and HBD.GetPlayerWorldPosition then
		local _, _, inst = HBD:GetPlayerWorldPosition()
		Route.hinted = Route.hinted or {}
		if inst and not Route.hinted[inst] and not Route.FlightsKnown(inst) then
			Route.hinted[inst] = true
			ns.Print(L["MapSeek doesn't know your flight paths on this continent yet, so routes here won't use flights. Open any flight master's map once and it will."])
		end
	end
	local steps, total = Route.Plan(d)
	if not steps or #steps == 0 then return false end
	-- (goal: where it's to, to plan it again from where you are when a step can't be taken)
	preview = nil   -- (a route on: it's drawn instead)
	route = { steps = steps, at = 1, total = total, dest = d.name or "?",
		goal = { ui = d.ui, x = d.x, y = d.y, name = d.name } }
	-- (where it began: the first step's way starts there, to tell when you're off it)
	if HBD and HBD.GetPlayerWorldPosition then
		local px, py, pinst = HBD:GetPlayerWorldPosition()
		if px then route.from = { px, py, pinst } end
	end
	Save()
	MakePanel()
	local lines = {}
	for i, s in ipairs(steps) do lines[i] = ("%d. %s"):format(i, s.text) end
	Say(L["Route to %s: about %s"]:format(route.dest, Minutes(total)) .. "  " .. table.concat(lines, "  "))
	PointAt(steps[1])
	Refresh()
	if ticker then ticker:Cancel() end
	ticker = C_Timer.NewTicker(TICK, Check)
	if DrawLine then DrawLine(true) end
	return true, route
end

--- go round a farming loop (Farm.lua) until it's stopped: d = { steps, first, total (a lap's
--- seconds), name }. Its steps are followed as a route's are; past the last, the first again.
--- From afar, the way to its first spot is followed first (flights, boats, your hearthstone), and
--- the loop taken up on arriving (d.direct: straight onto the loop)
function Route.StartLoop(d)
	if not (d and d.steps and #d.steps > 0) then return false end
	if not d.direct then
		local first = d.steps[d.first or 1].to
		local ok, started = pcall(Route.Start, { ui = first.ui, x = first.x, y = first.y, name = d.name })
		if ok and started and route then
			route.after = d
			Save()
			Refresh()
			return true, route
		end
	end
	d.direct = nil
	preview = nil   -- (a route on: it's drawn instead)
	route = { steps = d.steps, at = d.first or 1, total = d.total or 0, dest = d.name or "?", loop = true, lap = 1 }
	Save()
	MakePanel()
	Say(L["Farming %s: about %s a lap. It goes round until you stop it: /seek stop, or the X on the map's route panel."]
		:format(route.dest, Minutes(route.total)))
	PointAt(route.steps[route.at])
	Refresh()
	if ticker then ticker:Cancel() end
	ticker = C_Timer.NewTicker(TICK, Check)
	if DrawLine then DrawLine(true) end
	return true, route
end

function Route.Stop()
	local loop = route and (route.loop or route.after) and true or false
	route = nil
	Save()
	if DrawLine then DrawLine(true) end
	if ticker then ticker:Cancel() ticker = nil end
	if waypoint and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, waypoint) end
	waypoint = nil
	Refresh()
	if loop and ns.UI and ns.UI.RouteStopped then ns.UI.RouteStopped(true) end
	if ns.FarmList and ns.FarmList.RouteStopped then ns.FarmList.RouteStopped() end
end

function Route.Active() return route end

--- a farming loop looked at (Farm.lua's option: ui, spots), drawn in green while no route is on;
--- nil: none
function Route.Preview(o)
	preview = nil
	if o and o.spots then
		preview = {}
		for i, s in ipairs(o.spots) do
			preview[#preview + 1] = { ui = o.ui, x = s.x, y = s.y }
			-- (the way on to the next, over the terrain)
			for _, v in ipairs(o.legs and o.legs[i] and o.legs[i].via or {}) do preview[#preview + 1] = v end
		end
	end
	if DrawLine then DrawLine(true) end
end

--- whether a map is a city's (or in one): its streets are planned through its gates, not walked
function Route.InCity(ui) return ui and CITY[ZoneOf(ui)] and true or false end

--- seconds to get to d by the quickest way (riding, flights, boats, your hearthstone), or nil
--- when it can't be planned (no network for where you or it are)
function Route.Time(d)
	local ok, _, secs = pcall(Route.Plan, d, true)
	return ok and secs or nil
end

--- let the continents' networks go (the map closed a while ago, no route on: a couple of MB each,
--- read again from RouteNet.lua in a few ms the next time a route's planned)
function Route.Release()
	if not route then nets = {} end
end

--- plan the route being followed again, from where you are now (to the same place)
function Route.Recalculate()
	if not (route and route.goal) or route.loop then return end
	local goal, after = route.goal, route.after
	if Route.Start(goal) then
		if after then route.after = after Save() end
	elseif after then
		-- (the loop's near enough to ride straight to: onto it)
		after.direct = true
		Route.StartLoop(after)
	else
		-- (riding straight there is it now: the arrow there, the route done with)
		Route.Stop()
		ns.Pins.SetWaypoint(goal)
	end
end

-- (a reload or a log in: the route kept, followed again from the step it was at)
local resume = CreateFrame("Frame")
resume:RegisterEvent("PLAYER_ENTERING_WORLD")
resume:SetScript("OnEvent", function()
	if route then return end
	local r = Store()
	local kept = r and r.active and r.active[Me()]
	if not (kept and type(kept.steps) == "table" and kept.steps[kept.at or 1]) then return end
	route = { steps = kept.steps, at = kept.at or 1, total = kept.total or 0, dest = kept.dest or "?", goal = kept.goal,
		loop = kept.loop, lap = kept.lap, after = kept.after }
	-- (a moment on: the map and the waypoint are ready by then)
	C_Timer.After(2, function()
		if not route then return end
		PointAt(route.steps[route.at])
		if route.loop then
			Say(L["Farming %s: about %s a lap. It goes round until you stop it: /seek stop, or the X on the map's route panel."]
				:format(route.dest, Minutes(route.total)))
		else
			Say(L["Route to %s: about %s"]:format(route.dest, Minutes(route.total)) .. "  "
				.. L["Next: %s"]:format(route.steps[route.at].text))
		end
		if ticker then ticker:Cancel() end
		ticker = C_Timer.NewTicker(TICK, Check)
		if (WorldMapFrame and WorldMapFrame:IsShown()) or ns.db.routeOut then MakePanel() end
		Refresh()
		if DrawLine then DrawLine(true) end
	end)
end)

--------------------------------------------------------------------------------
-- The route on the world map: from you, through each step's place, a numbered dot at each.
-- Riding solid gold; flights dashed sky blue; boats, zeppelins and the like dashed teal; the
-- hearthstone no line (it's no journey). Done steps left off; it follows you as you go
--------------------------------------------------------------------------------

-- (the ground's way: the pink of a guide's line on the map, as RestedXP draws its own, with its
-- dark edge: what a line to follow looks like to anyone who's used one. The other ways keep
-- colours of their own, to tell them from it)
local LINE_COLOUR = { ride = { 0.98, 0.59, 1, 0.95 }, exit = { 0.98, 0.59, 1, 0.95 },
	fly = { 0.45, 0.8, 1, 0.95 }, transport = { 0.3, 1, 0.75, 0.95 }, hearth = { 0.75, 0.4, 1, 0.95 },
	pickup = { 0.98, 0.59, 1, 0.95 }, swim = { 0.3, 0.75, 1, 0.95 }, farm = { 0.35, 1, 0.45, 0.95 } }
local LINE_EDGE = { 0, 0, 0, 0.85 }   -- (under every line: a dark edge, a pixel a side)
local DASHED = { fly = true, transport = true, swim = true }
local LINE_NOW = { 1, 1, 1, 0.95 }   -- (the step you're on: white, whatever its kind; its dashes say which)
local LINE_PX, DASH_PX, GAP_PX, DOT_PX = 3, 12, 7, 18
local lineF, lineKey
local linePool, dotPool = {}, {}

local function Line(n, col, thick, under)
	local l = linePool[n]
	if not l then
		l = lineF:CreateLine(nil, "OVERLAY")
		linePool[n] = l
	end
	l:SetDrawLayer(under and "ARTWORK" or "OVERLAY")   -- (under: a line's dark edge, beneath the lines)
	l:SetColorTexture(col[1], col[2], col[3], col[4])
	l:SetThickness(thick)
	l:Show()
	return l
end

local function Dot(n)
	local d = dotPool[n]
	if not d then
		d = CreateFrame("Frame", nil, lineF)
		d:SetSize(DOT_PX, DOT_PX)
		d.bg = d:CreateTexture(nil, "ARTWORK")
		d.bg:SetAllPoints()
		d.bg:SetTexture("Interface\\WorldMap\\WorldMapPartyIcon")
		d.num = ns.Text(d, "GameFontNormalSmall")
		d.num:SetPoint("CENTER", 0, 0)
		ns.Outline(d.num, 10)
		d.num:SetTextColor(1, 1, 1)
		dotPool[n] = d
	end
	d:Show()
	return d
end

-- the line between two points of the canvas (units), solid or in dashes
local function Segment(n, ax, ay, bx, by, col, dashed, scale)
	local thick = LINE_PX / scale
	local edge = (LINE_PX + 2) / scale
	if not dashed then
		n = n + 1
		local u = Line(n, LINE_EDGE, edge, true)
		u:SetStartPoint("TOPLEFT", lineF, ax, -ay)
		u:SetEndPoint("TOPLEFT", lineF, bx, -by)
		n = n + 1
		local l = Line(n, col, thick)
		l:SetStartPoint("TOPLEFT", lineF, ax, -ay)
		l:SetEndPoint("TOPLEFT", lineF, bx, -by)
		return n
	end
	local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
	local dash, gap = DASH_PX / scale, GAP_PX / scale
	if len < 1 then return n end
	local ux, uy = (bx - ax) / len, (by - ay) / len
	local at = 0
	while at < len and n < 4000 do
		local e = math.min(len, at + dash)
		n = n + 1
		local u = Line(n, LINE_EDGE, edge, true)
		u:SetStartPoint("TOPLEFT", lineF, ax + ux * at, -(ay + uy * at))
		u:SetEndPoint("TOPLEFT", lineF, ax + ux * e, -(ay + uy * e))
		n = n + 1
		local l = Line(n, col, thick)
		l:SetStartPoint("TOPLEFT", lineF, ax + ux * at, -(ay + uy * at))
		l:SetEndPoint("TOPLEFT", lineF, ax + ux * e, -(ay + uy * e))
		at = e + gap
	end
	return n
end

DrawLine = function(force)
	local view = WorldMapFrame and WorldMapFrame.ScrollContainer
	local canvas = view and view.Child
	if not canvas then return end
	if not lineF then
		lineF = CreateFrame("Frame", nil, canvas)
		lineF:SetAllPoints(canvas)
		lineF:EnableMouse(false)
		local watch = CreateFrame("Frame", nil, WorldMapFrame)
		local since = 0
		watch:SetScript("OnUpdate", function(_, elapsed)
			since = since + elapsed
			if since < 0.1 then return end
			since = 0
			if route or preview or lineF:IsShown() then DrawLine() end
		end)
	end
	if not (route or preview) then
		lineF:Hide()
		lineKey = nil
		return
	end
	local w, h, scale = canvas:GetWidth(), canvas:GetHeight(), canvas:GetScale()
	local shown = WorldMapFrame:GetMapID()
	-- (you, on your map)
	local pm = ns.PlayerMap and ns.PlayerMap()
	local pos = pm and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(pm, "player")
	local px, py
	if pos then px, py = pos:GetXY() end
	local key = ("%s:%d:%d:%.4f:%d:%.3f:%.3f:%s"):format(tostring(shown), w, h, scale, route and route.at or 0,
		px or -1, py or -1, tostring(not route and preview))
	if key == lineKey and not force then return end
	lineKey = key
	if not (shown and w > 0) then lineF:Hide() return end
	lineF:SetFrameLevel(ns.Pins.UnderLevel and ns.Pins.UnderLevel() or 1)
	local function On(ui, x, y)   -- (a point on the canvas, units)
		local sx, sy = ns.Pins.ToShownMap(ui, x, y)
		if sx then return sx * w, sy * h end
	end
	local nL, nD = 0, 0
	local ax, ay
	if px and px > 0 then ax, ay = On(pm, px, py) end
	-- a farming loop, closed: { { ui, x, y (0..100) }, ... }
	local function Ring(pts)
		if #pts < 2 then return end
		local col = LINE_COLOUR.farm
		local last = pts[#pts]
		local lx, ly = On(last.ui, last.x / 100, last.y / 100)
		for _, p in ipairs(pts) do
			local bx, by = On(p.ui, p.x / 100, p.y / 100)
			if bx and lx then nL = Segment(nL, lx, ly, bx, by, col, false, scale) end
			lx, ly = bx, by
		end
	end
	-- (the steps still to go; a loop's all of them, from the next round to it again, closing it)
	local order, n = {}, route and #route.steps or 0
	if not route then
		-- (no route: the loop looked at)
	elseif route.loop then
		for k = 0, n do order[#order + 1] = (route.at - 1 + k) % n + 1 end
	else
		for i = route.at, n do order[#order + 1] = i end
	end
	for k, i in ipairs(order) do
		local s = route.steps[i]
		local closing = route.loop and k > n   -- (the loop's last leg: no second dot)
		local col = (k == 1 and not route.loop and LINE_NOW) or LINE_COLOUR[s.kind] or LINE_COLOUR.ride
		-- (the way there, point by point, then its end. The step you're on: from you, only the
		-- points still ahead of you, nearer its end than you are)
		local tx, ty = On(s.to.ui, s.to.x / 100, s.to.y / 100)
		local mine = k == 1 and ax and tx and (ax - tx) ^ 2 + (ay - ty) ^ 2
		for _, v in ipairs(s.via or {}) do
			local vx, vy = On(v.ui, v.x / 100, v.y / 100)
			if mine and vx and (vx - tx) ^ 2 + (vy - ty) ^ 2 >= mine then vx = nil end
			if vx and ax and s.kind ~= "hearth" then nL = Segment(nL, ax, ay, vx, vy, col, DASHED[s.kind], scale) end
			if vx then ax, ay = vx, vy end
		end
		local bx, by = On(s.to.ui, s.to.x / 100, s.to.y / 100)
		if bx and ax and s.kind ~= "hearth" then
			nL = Segment(nL, ax, ay, bx, by, col, DASHED[s.kind], scale)
		end
		if bx and not closing then
			nD = nD + 1
			local d = Dot(nD)
			local col = LINE_COLOUR[s.kind] or LINE_COLOUR.ride
			d.bg:SetVertexColor(col[1], col[2], col[3])
			d.num:SetText(i)
			d:SetScale(1 / math.max(scale, 0.01) * (i == route.at and 1.25 or 1))
			local ds = d:GetScale()
			d:ClearAllPoints()
			d:SetPoint("CENTER", lineF, "TOPLEFT", bx / ds, -by / ds)
		end
		ax, ay = bx, by
	end
	-- (on the way to a farming loop: the loop too, where it'll go round once you're there; no
	-- route, a loop looked at in the drop-down)
	local loop = route and route.after and route.after.steps
	if loop then
		local pts = {}
		for _, s in ipairs(loop) do
			for _, v in ipairs(s.via or {}) do pts[#pts + 1] = v end
			pts[#pts + 1] = s.to
		end
		Ring(pts)
	elseif not route and preview then
		Ring(preview)
	end
	for i = nL + 1, #linePool do linePool[i]:Hide() end
	for i = nD + 1, #dotPool do dotPool[i]:Hide() end
	lineF:Show()
end

-- the game's map pin (Ctrl-click on the map, or a map pin link in chat): the route there too.
-- (A pin taken off doesn't stop it: the game takes one off itself when you reach it. The X does)
local pins = CreateFrame("Frame")
pins:RegisterEvent("USER_WAYPOINT_UPDATED")
pins:SetScript("OnEvent", function()
	if GetTime() < ownPinUntil then return end
	local p = C_Map and C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
	if not p then return end
	local x, y = p.position and p.position.x, p.position and p.position.y
	if not (p.uiMapID and x and y) then return end
	local d = { ui = p.uiMapID, x = x * 100, y = y * 100, name = L["your map pin (%s)"]:format(ns.ZoneName(p.uiMapID) or "?") }
	Route.Start(d)
end)

-- (the map open: the panel made and shown, when there's a route)
if WorldMapFrame then
	WorldMapFrame:HookScript("OnShow", function()
		if route then
			MakePanel()
			if panel and not ns.db.routeOut then Place(panel) end
			Refresh()
		end
	end)
end
