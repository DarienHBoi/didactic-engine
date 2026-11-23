--------------------------------------------------------------------------------
-- The markers: the searched-for icon with a ring that pulses outward for a few seconds, then
-- (if kept) the icon alone until the search is cleared. Placed through Questie's copy of
-- HereBeDragons-Pins, which OpenMap also re-places on its stitched map; drawn on a layer of
-- our own over every other map icon (see "Our own layer").
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local Pins = {}
ns.Pins = Pins

local HBDPins = ns.MapLib and ns.MapLib("HBDPins", "AddWorldMapIconMap") or (LibStub and LibStub("HereBeDragons-Pins-2.0", true))
local HBD = ns.MapLib and ns.MapLib("HBD", "GetWorldCoordinatesFromZone") or (LibStub and LibStub("HereBeDragons-2.0", true))
local REF = "MapSeek"
local SHOW_CONTINENT = 2          -- HBD_PINS_WORLDMAP_SHOW_CONTINENT: on its zone, parent zones and the continent
local MINIMAP_MAX = 60            -- minimap markers at most (your current zone only)

local RING = "Interface\\Minimap\\Ping\\ping5"
local DOT = "Interface\\WorldMap\\WorldMapPartyIcon"   -- (an NPC with no service: a gold dot)
local GOLD = { 1, 0.82, 0.1 }

-- where a marker is, by name: its zone (or, for GM Island's vendors, the island)
local function Where(d) return d.place or ns.ZoneName(d.ui) end

--------------------------------------------------------------------------------
-- The marker's icon matches the search: the service searched for (repair, inn, trainer ...),
-- or for a name search, the NPC's own main service. Blizzard's minimap tracking icons, as
-- OpenMap's townsfolk use, each with a gossip icon to fall back on.
--------------------------------------------------------------------------------

local LOOKS = {
	SEARCH = { "Interface\\Icons\\INV_Misc_Spyglass_03" },   -- (a favourite's button, by default)
	FLIGHT_MASTER = { "Interface\\Minimap\\Tracking\\FlightMaster", "Interface\\GossipFrame\\TaxiGossipIcon" },
	INNKEEPER = { "Interface\\Minimap\\Tracking\\Innkeeper", "Interface\\GossipFrame\\BinderGossipIcon" },
	BANKER = { "Interface\\Minimap\\Tracking\\Banker", "Interface\\GossipFrame\\BankerGossipIcon" },
	AUCTIONEER = { "Interface\\Minimap\\Tracking\\Auctioneer", "Interface\\GossipFrame\\VendorGossipIcon" },
	STABLEMASTER = { "Interface\\Minimap\\Tracking\\StableMaster", "Interface\\GossipFrame\\PetitionGossipIcon" },
	BATTLEMASTER = { "Interface\\Minimap\\Tracking\\BattleMaster", "Interface\\GossipFrame\\BattleMasterGossipIcon" },
	REPAIR = { "Interface\\Minimap\\Tracking\\Repair", "Interface\\GossipFrame\\VendorGossipIcon" },
	CLASS = { "Interface\\Minimap\\Tracking\\Class", "Interface\\GossipFrame\\TrainerGossipIcon" },
	PROFESSION = { "Interface\\Minimap\\Tracking\\Profession", "Interface\\GossipFrame\\TrainerGossipIcon" },
	VENDOR = { "Interface\\GossipFrame\\VendorGossipIcon" },
	TABARD_DESIGNER = { "Interface\\GossipFrame\\TabardGossipIcon", "Interface\\GossipFrame\\VendorGossipIcon" },
	PETITIONER = { "Interface\\GossipFrame\\PetitionGossipIcon" },
	-- objects, and quest givers
	MAILBOX = { "Interface\\Minimap\\Tracking\\Mailbox", "Interface\\Icons\\INV_Letter_15" },
	FORGE = { "Interface\\Icons\\Trade_BlackSmithing" },
	ANVIL = { "Interface\\Icons\\INV_Hammer_20", "Interface\\Icons\\Trade_BlackSmithing" },
	COOKING = { "Interface\\Icons\\Spell_Fire_Fire", "Interface\\Icons\\INV_Misc_Food_15" },   -- (Basic Campfire's own)
	MEETING_STONE = { "Interface\\AddOns\\Questie\\Icons\\mstone.blp", "Interface\\Icons\\INV_Misc_Rune_01" },
	QUEST = { "Interface\\AddOns\\Questie\\Icons\\available.blp", "Interface\\GossipFrame\\AvailableQuestIcon" },
	QUEST_END = { "Interface\\AddOns\\Questie\\Icons\\complete.blp", "Interface\\GossipFrame\\ActiveQuestIcon" },
	DROPS = { "Interface\\Icons\\INV_Misc_Bag_10" },   -- (where an item drops, when its own icon isn't known)
	TOWN = { "Interface\\Icons\\Ability_TownWatch", "Interface\\Icons\\INV_Misc_Map_01" },   -- (a town searched for)
	-- (a dungeon's entrance: the game's own map icon for one, as FojjiCore's dungeon journal uses)
	DUNGEON = { "Interface\\Minimap\\Dungeon", atlas = "Dungeon" },
	SIGN = { "Interface\\Icons\\INV_Letter_15" },   -- (GM Island's sign)
	GROUP = { "Interface\\Icons\\Ability_Warrior_BattleShout", "Interface\\Icons\\INV_Misc_Head_Human_01" },   -- (your group)
	TRANSPORT = { "Interface\\Icons\\INV_Misc_Map_01" },   -- (a dock or tower: each marker carries its own icon)
}
-- someone in your group: their class's icon (a round one, when this client has it)
for class, coords in pairs(_G.CLASS_ICON_TCOORDS or {}) do
	LOOKS["MEMBER_" .. class] = { "Interface\\TargetingFrame\\UI-Classes-Circles",
		"Interface\\WorldStateFrame\\Icons-Classes", coords = coords }
end

-- what an object marker is, in its tooltip
local KIND_LABEL = { MAILBOX = L["Mailbox"], FORGE = L["Forge"], ANVIL = L["Anvil"], COOKING = L["Cooking fire"],
	MEETING_STONE = L["Meeting stone"], TOWN = L["Place"], DUNGEON = L["Dungeon entrance"], TRANSPORT = L["Transport"] }
ns.LOOKS = LOOKS

-- for a name search: the service an NPC is best known by, first that it has
local ORDER = { "FLIGHT_MASTER", "INNKEEPER", "BANKER", "AUCTIONEER", "STABLEMASTER", "BATTLEMASTER",
	"REPAIR", "TRAINER", "VENDOR", "TABARD_DESIGNER", "PETITIONER" }

local classNames
local function IsClassTrainer(sub)
	if not sub then return false end
	if not classNames then
		classNames = {}
		for _, t in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE or {}, _G.LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
			for _, name in pairs(t) do classNames[#classNames + 1] = name end
		end
	end
	for _, name in ipairs(classNames) do
		if sub:find(name, 1, true) then return true end
	end
	return false
end

local function KindFor(e, service, r)
	if r and r.kind then return r.kind end
	local key = service
	if not key then
		local enum = _G.LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.npcFlags
		if enum then
			for _, k in ipairs(ORDER) do
				if enum[k] and bit.band(e.flags, enum[k]) ~= 0 then key = k break end
			end
		end
	end
	if key == "TRAINER" then
		if e.pet then return "STABLEMASTER" end   -- (a hunter's pet trainer)
		return IsClassTrainer(e.sub) and "CLASS" or "PROFESSION"
	end
	return LOOKS[key] and key or nil
end

--- the look for a result's markers (a favourite's button takes its icon from its search)
function ns.KindOf(r, service)
	return KindFor(r.entry, service, r)
end

-- a texture from a look: the tracking icon, or its fallback when this client lacks it
function ns.SetLook(tex, look)
	-- (an atlas of the game's, when this client has it: it sets its own part of its texture)
	if look.atlas and tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo
		and C_Texture.GetAtlasInfo(look.atlas) and pcall(tex.SetAtlas, tex, look.atlas, false) then
		return
	end
	local path = look[1]
	if tex:SetTexture(path) == false and look[2] then
		path = look[2]
		tex:SetTexture(path)
	end
	-- (a part of the texture: a class's icon among them all)
	if look.coords then
		tex:SetTexCoord(look.coords[1], look.coords[2], look.coords[3], look.coords[4])
		return
	end
	-- (a spell or item icon has a border baked in: cut it off)
	if path:find("^Interface\\Icons\\") then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	else tex:SetTexCoord(0, 1, 0, 1) end
end

-- a marker with an icon of its own (an item's, where it drops)
local function IconLook(f, icon)
	f.kind = nil   -- (its look set again next time)
	f.dot:SetTexture(icon)
	f.dot:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.dot:SetVertexColor(1, 1, 1)
	f.dot:SetSize(f.size * 0.7, f.size * 0.7)
end

local function ApplyLook(f, kind)
	kind = kind or "dot"
	if f.kind == kind then return end
	f.kind = kind
	local dot, s = f.dot, f.size
	local look = LOOKS[kind]
	if look then
		ns.SetLook(dot, look)
		dot:SetVertexColor(1, 1, 1)
		dot:SetSize(s * 0.7, s * 0.7)
	else
		dot:SetTexture(DOT)
		dot:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
		dot:SetSize(s * 0.45, s * 0.45)
	end
end

-- Questie walks every pin of its HereBeDragons copy: its map tooltip and gamepad hover read
-- icon.data (and complain when it's missing), and its rescale on map change calls
-- data:GetIconScale(). This stub makes ours pass by quietly: `hidden` makes the tooltip and
-- gamepad hover skip them, and a scale of 0 leaves their size alone.
-- (Ours aren't flagged `miniMapIcon`, so Questie's minimap fade loop skips them too.)
-- World map anchors own their NPC's path (Questie hides a hidden owner's paths), so they get
-- their own data each time (NewData) and a see-through texture instead, which the tooltip and
-- gamepad hover skip just the same.
local function NoScale() return 0 end
local QUESTIE_STUB = { Id = 0, Type = "MapSeek", GetIconScale = NoScale }
local function NewData(npcId) return { Id = npcId, Type = "MapSeek", GetIconScale = NoScale } end

-- Questie's patrol paths (QuestieWaypoints, Questie 12.2+): Questie draws them on the zone's map,
-- OpenMap on its stitched map
local Waypoints
local function QuestieWaypoints()
	if Waypoints == nil then
		-- (no Questie: no paths drawn)
		local loader = _G.QuestieLoader
		local ok, W = false, nil
		if loader and loader.ImportModule then ok, W = pcall(loader.ImportModule, loader, "QuestieWaypoints") end
		Waypoints = ok and type(W) == "table" and type(W.Add) == "function" and W or false
	end
	return Waypoints or nil
end
local MAX_PATHS = 60              -- NPCs' paths drawn at most per search
local BEACON_MAX = 3              -- markers at most for each to get a beacon

local pool = { world = {}, mini = {} }
local active = {}
local flashTimer

--------------------------------------------------------------------------------
-- Waypoints (Blizzard's, or TomTom's when it's loaded)
--------------------------------------------------------------------------------

--- a waypoint to d (TomTom's when installed, else the game's). quiet: not said in chat (a
--- route's steps). Returns TomTom's waypoint, to take off later
function Pins.SetWaypoint(d, quiet)
	if TomTom and TomTom.AddWaypoint then
		return TomTom:AddWaypoint(d.ui, d.x / 100, d.y / 100, { title = d.name, from = "MapSeek" })
	end
	-- (FojjiCore's arrow, when it's there: the game's pin through its own call for one with a
	-- name, so its arrow says what it points at, a route's step. Its colours taken out)
	local FP = _G.FojjiCoreNS and FojjiCoreNS.DJ and FojjiCoreNS.DJ.Pins
	if type(FP) == "table" and type(FP.WaypointAt) == "function" and type(d.name) == "string" then
		local label = d.name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " ")
		local ok, done = pcall(FP.WaypointAt, d.ui, d.x / 100, d.y / 100, label, true)
		if ok and done then
			if not quiet then ns.Print(L["waypoint set: %s (%s %.1f, %.1f)"]:format(d.name, Where(d), d.x, d.y)) end
			return
		end
	end
	if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(d.ui) then
			ns.Print(L["can't set a waypoint on that map."])
			return
		end
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(d.ui, d.x / 100, d.y / 100))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
		if not quiet then ns.Print(L["waypoint set: %s (%s %.1f, %.1f)"]:format(d.name, Where(d), d.x, d.y)) end
	end
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

-- yards from you to a marker (nil on another continent, or when the game won't say)
local function Distance(d)
	if not (HBD and HBD.GetPlayerWorldPosition) then return end
	local px, py, pi = HBD:GetPlayerWorldPosition()
	if not px then return end
	local wx, wy, wi = HBD:GetWorldCoordinatesFromZone(d.x / 100, d.y / 100, d.ui)
	if not wx or wi ~= pi then return end
	return (HBD:GetWorldDistance(pi, px, py, wx, wy))
end
Pins.Distance = Distance

local GROUP_FEW = 3               -- a vendor's wares of each kind listed (all of them with Shift)
local FLY_FROM = 500              -- yards away from a marker before its nearest flight master shows

local ICON = 14                   -- item icons in the tooltip, px

-- what a skill book does: "Lets First Aid go past 150 (up to 225)"
local function BookNote(b)
	local skill = ns.Search.BOOK_NAMES[b.sub] or L["the skill"]
	return L["Lets %s go past %d (up to %d)"]:format(skill, b.from, b.to)
end

-- an item's name, in its quality's colour when it has one of note (GM Island's legendaries)
local function WareName(w)
	return w.quality == 5 and ("|cffff8000" .. w.name .. "|r") or w.name
end

-- one ware's line: its icon and name (and what it does, for a skill book)
local function AddWare(w, r, g, b)
	GameTooltip:AddLine(("  |T%s:%d|t %s"):format(ns.ItemIcon(w.id), ICON, WareName(w)), r, g, b)
	if w.book then GameTooltip:AddLine("      " .. BookNote(w.book), 0.6, 0.8, 1) end
end

-- a vendor's wares, by kind: a few of each kind (all of them when full). Returns whether any
-- were left out
local function Wares(list, skip, full)
	local groups = ns.Index.GROUPS
	local cur, shown, cutShort = nil, 0, false
	for _, w in ipairs(list) do
		if not (skip and skip[w.name]) then
			if w.group ~= cur then
				cur, shown = w.group, 0
				GameTooltip:AddLine(" " .. groups[cur], 0.6, 0.6, 0.6)
			end
			if full or shown < GROUP_FEW then
				AddWare(w, 0.85, 0.85, 0.85)
				shown = shown + 1
			else
				cutShort = true
			end
		end
	end
	return cutShort
end

--------------------------------------------------------------------------------
-- The nearest flight master to a marker (one your faction can fly from)
--------------------------------------------------------------------------------

local flights   -- { name, ui, wx, wy, wi } (world positions), built on first use

local function Flights()
	if flights then return flights end
	flights = {}
	local enum = _G.LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.npcFlags
	local FM, NpcDB = enum and enum.FLIGHT_MASTER, ns.Index.DB()
	if not (FM and HBD and NpcDB) then return flights end
	local mine = ns.faction == "Alliance" and "A" or "H"
	for _, e in ipairs(ns.Index.entries) do
		-- (the index keeps only "A" and "H": both factions, or neither, read from the data here)
		local fac = e.fac
		if not fac and bit.band(e.flags, FM) ~= 0 then
			local ok, f = pcall(NpcDB.Get, e.id, "friendlyToFaction")
			fac = ok and f or nil
		end
		if bit.band(e.flags, FM) ~= 0 and (fac == "AH" or fac == mine) then
			local ok, spawns = pcall(NpcDB.Get, e.id, "spawns")
			for areaId, list in pairs(ok and type(spawns) == "table" and spawns or {}) do
				local ui, s = ns.UiMapFor(areaId), type(list) == "table" and list[1]
				if ui and s and type(s[1]) == "number" and s[1] >= 0 then
					local wx, wy, wi = HBD:GetWorldCoordinatesFromZone(s[1] / 100, s[2] / 100, ui)
					if wx then flights[#flights + 1] = { name = e.name, ui = ui, wx = wx, wy = wy, wi = wi } end
				end
			end
		end
	end
	return flights
end

local function NearestFlight(d)
	if not HBD then return end
	local wx, wy, wi = HBD:GetWorldCoordinatesFromZone(d.x / 100, d.y / 100, d.ui)
	if not wx then return end
	local best, far
	for _, f in ipairs(Flights()) do
		if f.wi == wi then
			local yd = HBD:GetWorldDistance(wi, wx, wy, f.wx, f.wy)
			if yd and (not far or yd < far) then best, far = f, yd end
		end
	end
	return best, far
end

--------------------------------------------------------------------------------
-- Sharing a place in chat (shift-click a marker)
--------------------------------------------------------------------------------

local function Share(d)
	local text = ("%s%s: %s %.1f, %.1f"):format(d.name, d.sub and (" <" .. d.sub .. ">") or "",
		Where(d), d.x, d.y)
	local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
	if box then
		box:Insert(text)
	elseif ChatFrame_OpenChat then
		ChatFrame_OpenChat(text)
	end
end

-- (the tooltip redrawn when Shift goes down or up over a marker: everything it sells, or a few)
local shiftWatch = CreateFrame("Frame")

-- how long the quickest way to a marker takes (riding, flights, boats, your hearthstone), in
-- seconds; nil when it's close, or can't be planned. Only with the world map open, and not from a
-- city (its streets aren't in the networks: a route there goes by its gates). Kept until you move
local TRAVEL_NEAR = 100      -- yards: this close, the distance says it all
local TRAVEL_MOVE = 30       -- yards you move before they're worked out again
local travelAt, travelSecs = nil, {}
local function TravelTime(d, yd)
	if d.island or (yd and yd < TRAVEL_NEAR) then return end
	local R = ns.Route
	if not (R and R.Time and R.Minutes and WorldMapFrame and WorldMapFrame:IsShown()) then return end
	if R.InCity and ns.PlayerMap and R.InCity(ns.PlayerMap()) then return end
	if not (HBD and HBD.GetPlayerWorldPosition) then return end
	local px, py = HBD:GetPlayerWorldPosition()
	if not px then return end
	local at = ("%d:%d"):format(math.floor(px / TRAVEL_MOVE), math.floor(py / TRAVEL_MOVE))
	if at ~= travelAt then travelAt, travelSecs = at, {} end
	local spot = ("%d:%.2f:%.2f"):format(d.ui or 0, d.x or 0, d.y or 0)
	if travelSecs[spot] == nil then travelSecs[spot] = R.Time(d) or false end
	return travelSecs[spot] or nil
end

-- a marker's quests (a quest giver's, a hand-in's): the i-th's plain name, to show it by. The
-- tooltip's titles say more ("[42] Krol'dok Moulding", "The Lost Pilot: Faded Journal drops,
-- which starts it"); Search.lua keeps the names beside them. (On Pins, not locals of the file's:
-- Lua's limit of 200 locals in a chunk)
function Pins.QuestNameAt(d, i)
	return d.questNames and d.questNames[i] or d.quests[i]
end

-- right-click on a marker with quests: show its quest as searching for it does (the step you're
-- on, the chain, where to go); of several, a menu to pick one from
function Pins.ShowQuest(self, d)
	if #d.quests == 1 then ns.UI.SearchFromPin(Pins.QuestNameAt(d, 1)) return end
	local items = { { title = L["Show the quest:"] } }
	for i, t in ipairs(d.quests) do
		local name = Pins.QuestNameAt(d, i)
		items[#items + 1] = { text = t, func = function() ns.UI.SearchFromPin(name) end }
	end
	if not (ns.OpenMenu and ns.OpenMenu(self, items)) then ns.UI.SearchFromPin(Pins.QuestNameAt(d, 1)) end
end

local function OnEnter(self)
	local d = self.qms
	if not d then return end
	if ns.MapPaths and d.id then ns.MapPaths.Light(d.id) end   -- (its patrol path, lit while the mouse is on it)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(d.name, GOLD[1], GOLD[2], GOLD[3])
	if d.sub then GameTooltip:AddLine("<" .. d.sub .. ">", 1, 1, 1)
	elseif d.label or KIND_LABEL[d.kind] then GameTooltip:AddLine(d.label or KIND_LABEL[d.kind], 1, 1, 1) end
	local where = ("%s  %.1f, %.1f"):format(Where(d), d.x, d.y)
	local yd = not d.island and Distance(d)
	if yd then where = where .. "  " .. L["(%d yd)"]:format(yd)
	elseif d.island then where = where .. ("  (%s)"):format(Pins.DistanceGag()) end
	GameTooltip:AddLine(where, 0.75, 0.75, 0.75)
	local secs = TravelTime(d, yd)
	if secs then
		GameTooltip:AddLine(secs < 30 and L["Under a minute away"] or L["About %s away"]:format(ns.Route.Minutes(secs)),
			0.6, 0.8, 1)
	end
	-- (lines of its own: GM Island's NPCs have things to say)
	for _, l in ipairs(d.lines or {}) do GameTooltip:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1, true) end
	-- (a weapon master: the weapons it teaches)
	if d.teaches then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Teaches:"], 1, 0.82, 0.1)
		GameTooltip:AddLine(d.teaches, 1, 1, 1, true)
	end
	if d.quests then
		GameTooltip:AddLine(" ")
		if d.questStart then
			GameTooltip:AddLine(#d.quests == 1 and L["Starts the quest:"] or L["Starts the quests:"], 1, 0.82, 0.1)
		elseif d.questEnd then
			GameTooltip:AddLine(#d.quests == 1 and L["Hand in the quest here:"] or L["Hand in the quests here:"], 1, 0.82, 0.1)
		else
			GameTooltip:AddLine(#d.quests == 1 and L["Quest for you:"] or L["Quests for you:"], 1, 0.82, 0.1)
		end
		for i, q in ipairs(d.quests) do
			if i > 8 then GameTooltip:AddLine(L["and %d more"]:format(#d.quests - 8), 0.8, 0.8, 0.8) break end
			GameTooltip:AddLine("  " .. q, 1, 1, 1)
		end
		for _, l in ipairs(d.after or {}) do GameTooltip:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1, true) end
	end
	local wares = not d.obj and ns.Index.Wares(d.id)
	local skip
	if d.sells then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Sells:"], 0.5, 1, 0.5)
		skip = {}
		for _, s in ipairs(d.sells) do
			skip[s.name] = true
			AddWare(s, 0.5, 1, 0.5)
		end
	end
	if wares then
		local left = 0
		for _, w in ipairs(wares) do if not (skip and skip[w.name]) then left = left + 1 end end
		if left > 0 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(d.sells and L["Also sells:"] or L["Sells:"], 1, 0.82, 0.1)
			if Wares(wares, skip, IsShiftKeyDown()) then
				GameTooltip:AddLine("  " .. L["Hold Shift to see everything"], 0.5, 0.5, 0.5)
			end
		end
	end
	-- far off: where to fly to first
	if d.flightSelf then
		GameTooltip:AddLine(L["Nearest flight master: %s, %s (0 yd from it)"]:format(d.name, Where(d)), 0.6, 0.8, 1, true)
	elseif d.kind ~= "FLIGHT_MASTER" and not d.island and not (yd and yd < FLY_FROM) then
		local f, fyd = NearestFlight(d)
		if f then
			GameTooltip:AddLine(L["Nearest flight master: %s, %s (%d yd from it)"]:format(f.name,
				ns.ZoneName(f.ui), fyd), 0.6, 0.8, 1, true)
		end
	end
	GameTooltip:AddLine(L["Click to take me there"], 0.5, 1, 0.5)
	if wares or d.sells then
		GameTooltip:AddLine(L["Right-click to pin what it sells (hover items for stats)"], 0.5, 0.5, 0.5)
	elseif d.quest then
		GameTooltip:AddLine(L["Right-click to show the quest: %s"]:format(d.quest.name), 0.5, 0.5, 0.5)
	elseif d.quests and #d.quests == 1 then
		GameTooltip:AddLine(L["Right-click to show the quest: %s"]:format(Pins.QuestNameAt(d, 1)), 0.5, 0.5, 0.5)
	elseif d.quests and #d.quests > 1 then
		GameTooltip:AddLine(L["Right-click to show one of its quests"], 0.5, 0.5, 0.5)
	end
	GameTooltip:AddLine(L["Shift-click to share it in chat"], 0.5, 0.5, 0.5)
	GameTooltip:Show()
	shiftWatch.owner = self
	shiftWatch:RegisterEvent("MODIFIER_STATE_CHANGED")
end

shiftWatch:SetScript("OnEvent", function(self, _, key)
	local f = self.owner
	if key and not key:find("SHIFT") then return end
	if f and f:IsVisible() and GameTooltip:IsOwned(f) then OnEnter(f) end
end)

local function OnLeave()
	if ns.MapPaths then ns.MapPaths.Light(nil) end
	GameTooltip:Hide()
	shiftWatch.owner = nil
	shiftWatch:UnregisterEvent("MODIFIER_STATE_CHANGED")
end

--------------------------------------------------------------------------------
-- The pinned card (right-click a vendor's marker): everything it sells, staying put, so each
-- item can be hovered for the game's own tooltip (stats and all)
--------------------------------------------------------------------------------

local CARD_W, CARD_ROW, CARD_MAX = 250, 18, 22   -- width, row height, rows before it scrolls
local card, cardRows = nil, {}

local function CardRow(i)
	local r = cardRows[i]
	if r then return r end
	r = CreateFrame("Button", nil, card.content)
	r:SetSize(CARD_W - 40, CARD_ROW)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * CARD_ROW)
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	local icon = r:CreateTexture(nil, "ARTWORK")
	icon:SetSize(CARD_ROW - 2, CARD_ROW - 2)
	icon:SetPoint("LEFT", 4, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.icon = icon
	local text = ns.Text(r, "GameFontHighlightSmall")
	text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
	text:SetPoint("RIGHT", -2, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	r.text = text
	ns.SkinText(text)
	r:RegisterForClicks("LeftButtonUp")
	r:SetScript("OnEnter", function(self)
		if not self.item then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		-- (one of GM Island's: its own, made up, laid out as the game lays out an item's)
		if self.item < 0 then ns.FakeItemTooltip(self.item) else GameTooltip:SetItemByID(self.item) end
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- (shift-click: the item's link into chat; ctrl-click: try it on, as anywhere in the game)
	r:SetScript("OnClick", function(self)
		if not self.item then return end
		if self.item < 0 then
			-- (not a real item, so no real link: its name, in brackets, as plain text)
			local fake = ns.FakeItems[self.item]
			if fake and IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink("[" .. fake.name .. "]") end
			return
		end
		local _, link = GetItemInfo(self.item)
		if not link then return end
		if IsModifiedClick and HandleModifiedItemClick then
			HandleModifiedItemClick(link)
		elseif IsShiftKeyDown() and ChatEdit_InsertLink then
			ChatEdit_InsertLink(link)
		end
	end)
	cardRows[i] = r
	return r
end

local function MakeCard()
	card = CreateFrame("Frame", "MapSeekCard", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	card:SetFrameStrata("FULLSCREEN_DIALOG")   -- (over the world map)
	card:SetClampedToScreen(true)
	card:SetMovable(true)
	card:EnableMouse(true)
	card:RegisterForDrag("LeftButton")
	card:SetScript("OnDragStart", card.StartMoving)
	card:SetScript("OnDragStop", card.StopMovingOrSizing)
	if card.SetBackdrop then
		card:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		card:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
		card:SetBackdropBorderColor(0.6, 0.6, 0.6)
	end
	card.title = ns.Text(card, "GameFontNormal")
	card.title:SetPoint("TOPLEFT", 10, -10)
	card.title:SetPoint("RIGHT", -28, 0)
	card.title:SetJustifyH("LEFT")
	card.sub = ns.Text(card, "GameFontHighlightSmall")
	card.sub:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -2)
	card.sub:SetPoint("RIGHT", -10, 0)
	card.sub:SetJustifyH("LEFT")
	local close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	local scroll = CreateFrame("ScrollFrame", nil, card, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -44)
	scroll:SetPoint("BOTTOMRIGHT", -28, 24)
	card.content = CreateFrame("Frame", nil, scroll)
	card.content:SetSize(CARD_W - 40, 1)
	scroll:SetScrollChild(card.content)
	card.scroll = scroll
	card.hint = ns.Text(card, "GameFontDisableSmall")
	card.hint:SetPoint("BOTTOMLEFT", 10, 9)
	card.hint:SetText(L["Hover an item for its stats. Shift-click to link it."])
	-- (EUI: its flat panel, font, close button and scroll bar)
	ns.SkinPanel(card)
	ns.SkinText(card.title, card.sub, card.hint)
	ns.OnSkin(function(S)
		S.CloseButton(close)
		local bar = scroll.ScrollBar or (scroll:GetName() and _G[scroll:GetName() .. "ScrollBar"])
		if bar then S.ScrollBar(bar) end
	end)
	tinsert(UISpecialFrames, "MapSeekCard")   -- (Esc closes it)
	card:Hide()
end

-- the card's lines: the items searched for, then the rest by kind ({ head = text } or a ware)
local function CardLines(d)
	local lines, skip = {}, {}
	if d.sells then
		lines[#lines + 1] = { head = L["You searched for"], r = 0.5, g = 1, b = 0.5 }
		for _, s in ipairs(d.sells) do
			skip[s.name] = true
			lines[#lines + 1] = s
		end
	end
	local cur
	for _, w in ipairs(ns.Index.Wares(d.id) or {}) do
		if not skip[w.name] then
			if w.group ~= cur then
				cur = w.group
				lines[#lines + 1] = { head = ns.Index.GROUPS[cur] }
			end
			lines[#lines + 1] = w
		end
	end
	return lines
end

--- pin a vendor marker's wares in a card beside it
local function ShowCard(owner, d)
	if not card then MakeCard() end
	local lines = CardLines(d)
	card.title:SetText(d.name)
	card.sub:SetText(("%s%s  %.1f, %.1f"):format(d.sub and ("<" .. d.sub .. ">  ") or "", Where(d), d.x, d.y))
	for i, line in ipairs(lines) do
		local r = CardRow(i)
		if line.head then
			r.item = nil
			r.icon:Hide()
			r.text:SetPoint("LEFT", r, "LEFT", 4, 0)
			r.text:SetText(line.head)
			r.text:SetTextColor(line.r or 1, line.g or 0.82, line.b or 0.1)
			r:EnableMouse(false)
		else
			r.item = line.id
			r.icon:Show()
			r.icon:SetTexture(ns.ItemIcon(line.id))
			r.text:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
			r.text:SetText(line.book and (line.name .. "  |cff99ccff(" .. line.book.from .. " > "
				.. line.book.to .. ")|r") or WareName(line))
			r.text:SetTextColor(0.9, 0.9, 0.9)
			r:EnableMouse(true)
		end
		r:Show()
	end
	for i = #lines + 1, #cardRows do cardRows[i]:Hide() cardRows[i].item = nil end
	card.content:SetHeight(math.max(1, #lines * CARD_ROW))
	card:SetSize(CARD_W, 44 + math.min(#lines, CARD_MAX) * CARD_ROW + 28)
	card.scroll:SetVerticalScroll(0)
	-- (beside the marker, but on the screen itself: it stays when the map moves or the marker goes)
	card:ClearAllPoints()
	local s = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local x, y = owner:GetRight(), owner:GetTop()
	if x and y then
		card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x * s + 8, y * s)
	else
		card:SetPoint("CENTER")
	end
	card:Show()
	GameTooltip:Hide()
end

function Pins.HideCard()
	if card then card:Hide() end
end

-- a short message under a marker, as the game's own errors are worded and coloured, fading after
-- a moment (GM Island's: no waypoint goes there)
local gag
local function SayUnder(owner, text)
	if not gag then
		gag = CreateFrame("Frame", nil, UIParent)
		gag:SetFrameStrata("TOOLTIP")
		gag:SetSize(1, 1)
		local t = ns.Text(gag, "GameFontNormal")
		ns.Outline(t, size or 12)
		t:SetTextColor(1, 0.13, 0.13)
		t:SetPoint("TOP", gag, "TOP")
		t:SetWidth(260)
		gag.text = t
		local fade = gag:CreateAnimationGroup()
		local out = fade:CreateAnimation("Alpha")
		out:SetFromAlpha(1)
		out:SetToAlpha(0)
		out:SetStartDelay(2.2)
		out:SetDuration(0.8)
		fade:SetScript("OnFinished", function() gag:Hide() end)
		gag.fade = fade
	end
	gag.fade:Stop()
	gag:ClearAllPoints()
	-- (under it, on the screen: the marker's own scale is the map's)
	local s = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local x, y = owner:GetCenter()
	local b = owner:GetBottom()
	if x and b then
		gag:SetPoint("TOP", UIParent, "BOTTOMLEFT", x * s, b * s - 4)
	else
		gag:SetPoint("CENTER")
	end
	gag.text:SetText(text)
	gag:SetAlpha(1)
	gag:Show()
	gag.fade:Play()
end

local function OnClick(self, button)
	local d = self.qms
	if not d then return end
	if button == "RightButton" then
		if not d.obj and (d.sells or ns.Index.Wares(d.id)) then ShowCard(self, d)
		-- (an item a quest's for: the quest itself, as searching for it shows it)
		elseif d.quest and ns.UI.SearchFromPin then ns.UI.SearchFromPin(d.quest.name)
		-- (a quest giver's, a hand-in's: its quest; of several, the one you pick)
		elseif d.quests and #d.quests > 0 and ns.UI.SearchFromPin then Pins.ShowQuest(self, d) end
		return
	end
	if IsShiftKeyDown() then Share(d) return end
	if d.island then SayUnder(self, Pins.WaypointGag()) return end
	ns.UI.TakeMeThere(d)
end

--------------------------------------------------------------------------------
-- Our own layer, over every other icon on the map.
--
-- OpenMap draws its icons (boats, zeppelins, flight paths, townsfolk) on a clipping layer of
-- its own on the map's view (WorldMapFrame.ScrollContainer), not on the canvas where map pins
-- live, so no frame level on the canvas gets over them. So the world map markers are two
-- frames: an invisible anchor that Questie's HereBeDragons places on the canvas (and OpenMap
-- re-places on its stitched map), and the marker you see, on this layer: a sibling of
-- OpenMap's, on the same view, above it, held to its anchor and shown while it shows.
--------------------------------------------------------------------------------

local FLOOR = 2150                -- at least: above Questie's own icons (they start at 2016)
local OVERLAY_GAP = 8000          -- (OpenMap's dungeon view and cards sit this far over the view: stay under)

local holder

-- the level over the map's icons: Blizzard's topmost pin level, OpenMap's icon level, and the
-- clipping layers on the view (OpenMap's icon layer), but not its dungeon view and cards
local function TopLevel(view)
	local top = FLOOR
	local fl = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
	if fl and fl.GetValidFrameLevel then
		for _, name in ipairs({ "PIN_FRAME_LEVEL_OPENMAP_ICONS", "PIN_FRAME_LEVEL_TOPMOST" }) do
			local ok, l = pcall(fl.GetValidFrameLevel, fl, name)
			if ok and type(l) == "number" then top = math.max(top, l + 20) end
		end
	end
	local ceiling = view:GetFrameLevel() + OVERLAY_GAP
	for _, c in ipairs({ view:GetChildren() }) do
		if c ~= holder and c.DoesClipChildren and c:DoesClipChildren() then
			local l = c:GetFrameLevel()
			if l < ceiling then top = math.max(top, l + 20) end
		end
	end
	return math.min(top, ceiling - 1)
end

-- the layer back on top (OpenMap builds its layer when the map first opens)
function Pins.Raise()
	if not holder then return end
	local level = TopLevel(holder:GetParent())
	if holder:GetFrameLevel() ~= level then holder:SetFrameLevel(level) end
end

local function Holder()
	if holder then return holder end
	local view = WorldMapFrame and WorldMapFrame.ScrollContainer
	if not view then return end
	holder = CreateFrame("Frame", "MapSeekLayer", view)
	holder:SetAllPoints(view)
	if holder.SetClipsChildren then holder:SetClipsChildren(true) end   -- (cut at the map's edges, like the map)
	holder:EnableMouse(false)
	Pins.Raise()
	return holder
end

--- our layer over the map (for the route's steps, and the like)
function Pins.Layer() return Holder() end

--- the frame level on the map's canvas just under the markers, over the map's art (a route's line)
function Pins.UnderLevel()
	local view = WorldMapFrame and WorldMapFrame.ScrollContainer
	return view and math.max(1, TopLevel(view) - 4) or 1
end

-- /seek debug: where the layers sit
function Pins.Debug()
	local view = WorldMapFrame and WorldMapFrame.ScrollContainer
	if not view then ns.Print("no map view") return end
	ns.Print(("view %d (%s), our layer %s"):format(view:GetFrameLevel(), view:GetFrameStrata(),
		holder and (holder:GetFrameLevel() .. " " .. holder:GetFrameStrata()) or "not made yet"))
	for i, c in ipairs({ view:GetChildren() }) do
		local clips = c.DoesClipChildren and c:DoesClipChildren()
		print(("  child %d: %s level %d %s%s"):format(i, c:GetName() or "?", c:GetFrameLevel(),
			c:GetFrameStrata(), clips and " (clips)" or ""))
	end
	local fl = WorldMapFrame:GetPinFrameLevelsManager()
	for _, name in ipairs({ "PIN_FRAME_LEVEL_OPENMAP_ICONS", "PIN_FRAME_LEVEL_TOPMOST" }) do
		local ok, l = pcall(fl.GetValidFrameLevel, fl, name)
		print(("  %s: %s"):format(name, ok and tostring(l) or "n/a"))
	end
end

-- The marker follows its anchor being shown or hidden itself: HereBeDragons shows it when it
-- places it and hides it when it takes it off (or it belongs to another map). Not the anchor's
-- pin being hidden around it: OpenMap hides other addons' pins while the map zooms (they're
-- laid out again on every frame of it), but ours are on their own layer and cost nothing
-- there, so they stay, rather than dropping out and coming back after the zoom.
local function AnchorShown(self) if self.marker.qms then self.marker:Show() end end
local function AnchorHidden(self) self.marker:Hide() end

local function Make(mini)
	local size = mini and 18 or 28
	local layer = not mini and Holder()
	local f = CreateFrame("Button", nil, layer or UIParent)
	f:Hide()                      -- (shown when it's placed)
	f:SetSize(size, size)
	f.mini = mini

	if layer then
		-- what HereBeDragons places: Questie walks it as one of its pins, hence the stub
		local a = CreateFrame("Frame", nil, UIParent)
		a:Hide()
		a:SetSize(1, 1)
		a.data = QUESTIE_STUB
		local see = a:CreateTexture(nil, "ARTWORK")   -- (see-through: Questie's tooltip skips it)
		see:SetAllPoints()
		see:SetColorTexture(1, 1, 1, 1)
		see:SetVertexColor(1, 1, 1, 0)
		see.r, see.g, see.b, see.a = 1, 1, 1, 0      -- (as Questie keeps them on its icons' textures)
		a.texture = see
		a.marker = f
		hooksecurefunc(a, "Show", AnchorShown)
		hooksecurefunc(a, "Hide", AnchorHidden)
		f.anchor = a
		f:SetPoint("CENTER", a, "CENTER")
	else
		-- (the minimap's, or no view to hang a layer on: the marker is the pin itself)
		f.data = QUESTIE_STUB
		f.hidden = true
	end

	local ring = f:CreateTexture(nil, "OVERLAY", nil, 1)
	ring:SetTexture(RING)
	ring:SetBlendMode("ADD")
	ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	ring:SetAllPoints()
	f.ring = ring

	-- the nearest match's: a steady ring round it
	local halo = f:CreateTexture(nil, "OVERLAY", nil, 0)
	halo:SetTexture(RING)
	halo:SetBlendMode("ADD")
	halo:SetVertexColor(0.4, 1, 0.4, 0.9)
	halo:SetPoint("CENTER")
	halo:SetSize(size * 1.25, size * 1.25)
	halo:Hide()
	f.halo = halo

	local dot = f:CreateTexture(nil, "OVERLAY", nil, 2)   -- the icon (ApplyLook)
	dot:SetPoint("CENTER")
	f.dot = dot
	f.size = size
	ApplyLook(f, nil)

	-- the ring grows and fades, over and over
	local pulse = ring:CreateAnimationGroup()
	pulse:SetLooping("REPEAT")
	local grow = pulse:CreateAnimation("Scale")
	if grow.SetScaleFrom then
		grow:SetScaleFrom(0.3, 0.3)
		grow:SetScaleTo(1.6, 1.6)
	else
		grow:SetScale(5, 5)
	end
	grow:SetOrigin("CENTER", 0, 0)
	grow:SetDuration(0.9)
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetDuration(0.9)
	f.pulse = pulse

	-- the beacon: a wide, slow ripple that keeps going, for a search with only a few markers
	-- (one marker on a whole map is easy to miss)
	if not mini then
		local beacon = f:CreateTexture(nil, "OVERLAY", nil, 0)
		beacon:SetTexture(RING)
		beacon:SetBlendMode("ADD")
		beacon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
		beacon:SetPoint("CENTER")
		beacon:SetSize(size, size)
		beacon:Hide()
		-- (its ripple worked out each frame, not a looping animation: that one caught for a frame
		-- every time it began again, the ring back at full strength before it was let go. Here it
		-- comes up from nothing as it sets out, and is gone by the time it's widest, so where one
		-- ripple ends and the next begins there's nothing to see)
		local SECS, FROM, TO, MOST, RISE = 1.8, 0.6, 4.5, 0.9, 0.12
		local driver = CreateFrame("Frame", nil, f)
		driver:Hide()
		local t = 0
		driver:SetScript("OnUpdate", function(_, elapsed)
			t = (t + math.min(elapsed, 0.1)) % SECS
			local p = t / SECS
			local s = size * (FROM + (TO - FROM) * p)
			beacon:SetSize(s, s)
			beacon:SetAlpha(MOST * math.min(1, p / RISE) * (1 - p))
		end)
		local wave = {
			Play = function() t = 0 beacon:SetAlpha(0) driver:Show() end,
			Stop = function() driver:Hide() end,
			IsPlaying = function() return driver:IsShown() end,
		}
		f.beacon, f.wave = beacon, wave
	end

	-- the icon throbs while the ring pulses
	local throb = dot:CreateAnimationGroup()
	throb:SetLooping("BOUNCE")
	local dim = throb:CreateAnimation("Alpha")
	dim:SetFromAlpha(1)
	dim:SetToAlpha(0.5)
	dim:SetDuration(0.45)
	f.throb = throb

	f:SetScript("OnEnter", OnEnter)
	f:SetScript("OnLeave", OnLeave)
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")   -- (take me there; a vendor's card)
	f:SetScript("OnClick", OnClick)
	return f
end

-- A farming loop's veins and plants on the minimap, as on the map: where each may be. One you're near enough for the game's own Find Minerals or Find Herbs to
-- show, if it's there, is hidden: within that range the game's own dot is the truth, and no dot
-- means it isn't up
local TRACK_RANGE = 90        -- yards the game's tracking reaches (about: its dots come in at this)
local FARM_MINI_MAX = 400
local TRACK_ICON = { ore = { [136025] = true, earthquake = true }, herb = { [133939] = true, flower_02 = true } }
local farmMinis, farmTicker = {}, nil
local farmUp = false   -- a farming loop's veins, herbs or mobs are what's on the map
--- whether what's on the map is a farming loop's
function Pins.HasFarm() return farmUp end

-- which of Find Minerals and Find Herbs is on: { ore = true, herb = true }
local function Tracking()
	local on = {}
	local function See(tex)
		for kind, icons in pairs(TRACK_ICON) do
			if icons[tex] then on[kind] = true end
			if type(tex) == "string" then
				local l = tex:lower()
				for k in pairs(icons) do if type(k) == "string" and l:find(k, 1, true) then on[kind] = true end end
			end
		end
	end
	if GetTrackingTexture then
		local ok, tex = pcall(GetTrackingTexture)
		if ok and tex then See(tex) end
	end
	local M = C_Minimap
	if M and M.GetNumTrackingTypes and M.GetTrackingInfo then
		local okN, n = pcall(M.GetNumTrackingTypes)
		for i = 1, okN and n or 0 do
			local ok, a, b, c = pcall(M.GetTrackingInfo, i)
			if ok then
				-- (a table in newer clients, else name, texture, active)
				if type(a) == "table" then if a.active then See(a.texture) end
				elseif c then See(b) end
			end
		end
	end
	return on
end

-- (a marker's on the minimap only while you're near enough for it to show there: the library
-- places every one it's given, each time you move)
local FARM_MINI_NEAR = 400
local dot = { hold = 4 }      -- hold: seconds a real dot seen at a marker keeps it hidden (it's looked at again each second). (The rest: below)
local FARM_MINI_ALPHA = 0.8   -- fainter than the game's own dots: where one may be, not where one is
local trackOn, trackAt = {}, -10
local function FarmMiniTick()
	if #farmMinis == 0 or not (HBD and HBD.GetPlayerWorldPosition) then return end
	local px, py, pinst = HBD:GetPlayerWorldPosition()
	if not px then return end
	if GetTime() - trackAt > 2 then trackOn, trackAt = Tracking(), GetTime() end
	if dot.Look then dot.Look(px, py, pinst) end
	for _, m in ipairs(farmMinis) do
		local d2 = m.inst == pinst and (m.wx - px) ^ 2 + (m.wy - py) ^ 2 or math.huge
		local want = d2 <= FARM_MINI_NEAR * FARM_MINI_NEAR
		if want ~= m.on then
			m.on = want
			if want then HBDPins:AddMinimapIconMap(REF, m.frame, m.ui, m.x / 100, m.y / 100, false, false)
			else HBDPins:RemoveMinimapIcon(REF, m.frame) m.frame:Hide() end
		end
		if want then
			local a = FARM_MINI_ALPHA
			if trackOn[m.kind] then
				if dot.On() and dot.works then   -- (works: it's read a dot, this session; until then, as without it)
					-- (the game's own dot seen there, lately: its dot is the real thing)
					if m.real and GetTime() - (m.realAt or 0) < dot.hold and d2 <= (TRACK_RANGE * 1.4) ^ 2 then a = 0 end
				elseif d2 <= TRACK_RANGE * TRACK_RANGE then
					a = 0
				end
			end
			m.frame:SetAlpha(a)
		end
	end
end

--------------------------------------------------------------------------------
-- The game's own tracking dots, looked for where a farming loop's markers are (an option: "dots").
-- WoW Forever's minimap can be asked what it shows at a point of the screen, as if the mouse were
-- there (Minimap:UpdateMouseoverAtPoint, then C_TooltipInfo.GetMinimapMouseover). So, each second,
-- for each marker near enough for the game's tracking to show it: the minimap's asked what's at
-- the marker's spot. A vein or herb of the marker's name there: the marker hides, the game's dot
-- showing instead. Nothing's moved and nothing blinks. Only with Find Minerals or Find Herbs on,
-- and out of a fight
--------------------------------------------------------------------------------

do
local DOT_EVERY = 1      -- seconds between looks (every marker in reach)
local DOT_RANGE = 120    -- yards: the game's tracking shows nothing further off
local DOT_SHIFT = { { 0, 0 }, { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 }, { 5, 5 }, { -5, 5 }, { 5, -5 }, { -5, -5 } }   -- (about the spot: the data's a little off, at times)
local dotAt = -10
local DOT_ARROW = 12     -- pixels about the minimap's middle that your own arrow covers

function dot.On()
	return ns.db.dots and Minimap and Minimap.UpdateMouseoverAtPoint and Minimap.SetUsingSoftCursor
		and C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover and C_Minimap and C_Minimap.GetViewRadius and true or false
end

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

-- what the minimap shows at a point of the screen: whether it's the marker's vein or herb
local function DotRead(m, sx, sy)
	Minimap:UpdateMouseoverAtPoint(sx, sy)
	local data = C_TooltipInfo.GetMinimapMouseover()
	if type(data) ~= "table" or Secret(data) or type(data.lines) ~= "table" or Secret(data.lines) then return false end
	for _, line in ipairs(data.lines) do
		local t = line.leftText
		if type(t) == "string" and not Secret(t) then
			if m.name ~= "" and t:lower():find(m.name, 1, true) then
				dot.works = true
				return true
			end
		end
	end
	return false
end

-- every marker in the tracking's reach looked at (FarmMiniTick: each half second; here, each second)
function dot.Look(px, py, pinst)
	local now = GetTime()
	if now - dotAt < DOT_EVERY or not dot.On() then return end
	dotAt = now
	if InCombatLockdown() or not Minimap:IsVisible() then return end
	local okR, R = pcall(C_Minimap.GetViewRadius)
	if not okR or type(R) ~= "number" or Secret(R) or R <= 0 then return end
	local rot = GetCVar and GetCVar("rotateMinimap") == "1"
	local f = rot and GetPlayerFacing and GetPlayerFacing() or 0
	if type(f) ~= "number" or Secret(f) then return end
	local half = Minimap:GetWidth() / 2
	local s = Minimap:GetEffectiveScale()
	local mx, my = Minimap:GetCenter()
	if not (mx and s and s > 0 and half > 0) then return end
	local soft = false
	for _, m in ipairs(farmMinis) do
		local d2 = (m.wx - px) ^ 2 + (m.wy - py) ^ 2
		if m.on and trackOn[m.kind] and m.inst == pinst and d2 <= (R * 0.95) ^ 2 and d2 <= DOT_RANGE * DOT_RANGE then
			-- (where its spot is on the minimap, from the middle: east and north of you, turned with
			-- the minimap when it turns)
			local e, n = -(m.wx - px), m.wy - py
			if rot then e, n = e * math.cos(f) + n * math.sin(f), -e * math.sin(f) + n * math.cos(f) end
			local ox, oy = e / R * half, n / R * half
			if ox * ox + oy * oy <= DOT_ARROW * DOT_ARROW then
				-- (under your own arrow, in the minimap's middle: the game says nothing of what's
				-- there. A dot seen as you came up to it is still there)
				if m.real then m.realAt = now end
			else
				if not soft then soft = true Minimap:SetUsingSoftCursor(true) end
				local hit = false
				for _, sh in ipairs(DOT_SHIFT) do
					local ok, got = pcall(DotRead, m, (mx + ox + sh[1]) * s, (my + oy + sh[2]) * s)
					if ok and got then hit = true break end
				end
				m.real, m.realAt = hit, now
			end
		end
	end
	if soft then Minimap:SetUsingSoftCursor(false) end
end
end

local function Acquire(mini)
	local list = mini and pool.mini or pool.world
	local f = tremove(list) or Make(mini)
	active[#active + 1] = f
	return f
end

local function StartFlash(f)
	-- (the small ring's pulse, for a search of many markers: not on one with the wide ripple
	-- going, where the two together are only a clutter)
	if f.wave and f.wave.IsPlaying() then
		f.pulse:Stop()
		f.ring:Hide()
	else
		f.ring:Show()
		f.pulse:Play()
	end
	f.throb:Play()
end

local function StopFlash(f)
	f.pulse:Stop()
	f.throb:Stop()
	f.ring:Hide()
	f.dot:SetAlpha(1)
end

--------------------------------------------------------------------------------

local StartBig, StopBig           -- (below: a new search's markers start big)

function Pins.Available() return HBDPins ~= nil end

--------------------------------------------------------------------------------
-- Shh: an island that isn't anywhere ("gm island", UI.lua). Drawn by MapSeek out in the open sea,
-- on a continent's map, not in any zone or area; a different spot each time
--------------------------------------------------------------------------------

local ISLAND = "Interface\\AddOns\\MapSeek\\Media\\gmisland"
local CONTINENTS = { 1414, 1415 }   -- Kalimdor, the Eastern Kingdoms
local island
local ToShownMap   -- (a point of a zone's map on the map shown: below)

-- each zone's rectangle on a continent's map (minX, maxX, minY, maxY), read once: the zones cover
-- all its land, so outside all of them is sea
local zoneRects = {}
-- how far GM Island is: never a number of yards
local DISTANCE_GAGS = {
	"Not reachable by boat, mount or prayer",
	"999,999 yd, give or take",
	"Closer than it looks",
	"Further than it looks",
	"Distance: classified",
	"Several hearthstones away",
	"Swim speed not found",
}
function Pins.DistanceGag() return DISTANCE_GAGS[math.random(#DISTANCE_GAGS)] end

-- and a waypoint to it: never set
local WAYPOINT_GAGS = {
	"Waypoint rejected: GM Island isn't on any map.",
	"Your compass is spinning.",
	"The waypoint sank.",
	"TomTom says no.",
	"Waypoint set. Waypoint unset. Nobody saw anything.",
	"You need a GM to set a waypoint there. They're all on break.",
	"The arrow points down. Further down.",
}
function Pins.WaypointGag() return WAYPOINT_GAGS[math.random(#WAYPOINT_GAGS)] end

local function ZoneRects(cont)
	if zoneRects[cont] then return zoneRects[cont] end
	local rects = {}
	local ok, kids = pcall(C_Map.GetMapChildrenInfo, cont, nil, true)
	if ok and type(kids) == "table" then
		for _, k in ipairs(kids) do
			-- (zones and cities; the dungeons and caves are inside them)
			if k.mapType == 3 or k.mapType == 5 then
				local ok2, x0, x1, y0, y1 = pcall(C_Map.GetMapRectOnMap, k.mapID, cont)
				if ok2 and x0 and x1 and y0 and y1 and x1 > x0 and y1 > y0 then rects[#rects + 1] = { x0, x1, y0, y1 } end
			end
		end
	end
	if #rects > 0 then zoneRects[cont] = rects end   -- (none: not read yet, try again next time)
	return rects
end

local SEA_MARGIN = 0.03          -- this far clear of any zone (of the continent's map)

-- open sea at a spot of a continent's map: outside every zone (and the game says no zone's there)
local function OpenSea(cont, x, y, rects)
	for _, r in ipairs(rects) do
		if x > r[1] - SEA_MARGIN and x < r[2] + SEA_MARGIN and y > r[3] - SEA_MARGIN and y < r[4] + SEA_MARGIN then
			return false
		end
	end
	if C_Map.GetMapInfoAtPosition then
		local ok, info = pcall(C_Map.GetMapInfoAtPosition, cont, x, y)
		if ok and info and info.mapID ~= cont then return false end
	end
	return true
end

--- a spot of open sea, on a continent's map: well clear of every zone. Far out west of Kalimdor
--- if none's found (or the zones can't be read)
function Pins.IslandSpot()
	if C_Map and C_Map.GetMapChildrenInfo and C_Map.GetMapRectOnMap then
		for _ = 1, 200 do
			local ui = CONTINENTS[math.random(#CONTINENTS)]
			local rects = ZoneRects(ui)
			if #rects > 0 then
				local x, y = 0.07 + math.random() * 0.86, 0.07 + math.random() * 0.86
				if OpenSea(ui, x, y, rects) then return ui, x, y end
			end
		end
	end
	return 1414, 0.1, 0.5
end

local Q = "Interface\\Icons\\"

-- Its wares: made up, every one, with ids below zero (no real item has one), so the tooltips,
-- the pinned card and its rows treat them as they do a real vendor's (Core's ItemIcon and
-- Index.Wares hand these back for them). group: as Index.GROUPS (6 weapons, 7 armor, 8 bags,
-- 9 mounts & pets, 10 other)
local FAKE = {
	[-101] = { name = "Ban Hammer of the Ancients", icon = Q .. "INV_Hammer_20", group = 6, slot = "Two-Hand",
		type = "Mace", dmg = "999 - 1500", speed = "3.60", dps = "(346.8 damage per second)",
		stats = { "+999 Moderation", "+255 Stamina" }, dur = 255, req = 60,
		effect = "Use: Removes the target from the realm. (Cooldown: never)" },
	[-102] = { name = "Robe of the Game Master", icon = Q .. "INV_Misc_Rune_01", group = 7, slot = "Chest",
		type = "Cloth", armor = 9001, stats = { "+255 Intellect", "+255 Spirit" }, dur = 255, req = 60,
		effect = "Equip: You can't be seen by anyone with an open ticket." },
	[-103] = { name = "Spatula of Infinite Mana", icon = Q .. "INV_Misc_Food_15", group = 6, slot = "Held In Off-hand",
		stats = { "+1 Spatula Skill" }, req = 60, flavor = "It's not for cooking." },
	[-104] = { name = "Shoulderpads of Excessive Size", icon = Q .. "Trade_BlackSmithing", group = 7, slot = "Shoulder",
		type = "Plate", armor = 4800, stats = { "+80 Strength", "+80 Presence" }, dur = 120, req = 60,
		effect = "Equip: Doorways are now a problem." },
	[-105] = { name = "Bag of Hoarding Absolutely Everything", icon = Q .. "INV_Misc_Gear_01", group = 8, unique = true,
		slots = "255 Slot Bag", flavor = "Including the kitchen sink. It's in there somewhere." },
	[-106] = { name = "Pocket Murloc", icon = Q .. "INV_Misc_Head_Murloc_01", group = 9, unique = true,
		effect = "Use: Summons a murloc who won't stop talking.", flavor = "Mrglglglgl." },
	[-107] = { name = "Ticket of Eventual Reply", icon = Q .. "INV_Letter_15", group = 10, unique = true,
		flavor = "Your ticket is number 4,812 in the queue." },
	[-108] = { name = "Boots of Instant Teleportation", icon = Q .. "Ability_Tracking", group = 7, slot = "Feet",
		type = "Leather", armor = 500, stats = { "+30 Agility" }, dur = 90, req = 60,
		effect = "Use: Teleports you to GM Island. You are already here." },
	[-109] = { name = "Hearthstone of Somewhere Else", icon = Q .. "INV_Misc_Rune_01", group = 10, unique = true,
		effect = "Use: Returns you to an inn you've never been to. Speak to an Innkeeper in a different place to change your home location." },
	[-110] = { name = "Map to GM Island", icon = Q .. "INV_Misc_Map_01", group = 10, unique = true,
		flavor = "It's blank. That's how you know it's real." },
	[-111] = { name = "Oar of the Unsailed Sea", icon = Q .. "Ability_TownWatch", group = 6, slot = "Two-Hand",
		type = "Staff", dmg = "200 - 310", speed = "3.40", dps = "(75.0 damage per second)",
		stats = { "+20 Rowing" }, dur = 100, req = 55, effect = "Equip: You row in circles." },
	[-112] = { name = "Ferry Ticket (Cancelled)", icon = Q .. "INV_Letter_15", group = 10,
		flavor = "Sailings suspended until further notice." },

	-- Gamemaster Grizzlebeard's, more
	[-113] = { name = "Thunderfury, Blessed Blade of the Ticketseeker", icon = Q .. "INV_Sword_04", group = 6,
		slot = "One-Hand", type = "Sword", dmg = "44 - 84", speed = "1.90", dps = "(33.7 damage per second)",
		stats = { "+5 Agility", "+8 Stamina", "+8 Nature Resistance" }, dur = 125, req = 60,
		effect = "Chance on hit: Blasts your enemy with lightning, and your ticket with silence." },
	[-114] = { name = "Crown of Absolute Authority", icon = Q .. "INV_Helmet_01", group = 7, slot = "Head",
		type = "Plate", armor = 900, stats = { "+60 Strength", "+60 Authority" }, dur = 100, req = 60,
		effect = "Equip: Players /bow to you on sight." },
	[-115] = { name = "Ring of Eternal Uptime", icon = Q .. "INV_Jewelry_Ring_03", group = 7, slot = "Finger",
		unique = true, stats = { "+20 Stamina" }, req = 60,
		effect = "Equip: The servers never go down while you're online. Probably." },
	[-116] = { name = "Cloak of Server Restarts", icon = Q .. "INV_Misc_Cape_01", group = 7, slot = "Back",
		armor = 120, stats = { "+15 All Resistances" }, req = 60,
		effect = "Use: Sends everyone nearby back to the login screen. (Cooldown: 1 week)" },
	[-117] = { name = "Orb of Undo", icon = Q .. "INV_Misc_Orb_01", group = 10, unique = true, req = 60,
		effect = "Use: Undoes your last mistake. Does not work on guild drama." },
	[-118] = { name = "Gift-Wrapped Legendary", icon = Q .. "INV_Misc_Gift_01", group = 10, unique = true,
		flavor = "Do not open until patch day." },

	-- Quartermaster Null's, more
	[-119] = { name = "Placeholder Sword (Do Not Ship)", icon = Q .. "INV_Misc_QuestionMark", group = 6,
		slot = "One-Hand", type = "Sword", dmg = "1 - 1", speed = "1.00", dps = "(1.0 damage per second)",
		dur = 1, req = 1, flavor = "TODO: art." },
	[-120] = { name = "Gauntlets of Missing Textures", icon = Q .. "INV_Gauntlets_04", group = 7, slot = "Hands",
		type = "Plate", armor = 404, stats = { "+0 Visibility" }, dur = 55, req = 60,
		flavor = "In testing they were bright purple and green." },
	[-121] = { name = "Belt of Infinite Loops", icon = Q .. "INV_Belt_01", group = 7, slot = "Waist",
		type = "Leather", armor = 128, stats = { "+12 Agility" }, dur = 40, req = 55,
		effect = "Equip: Your belt never ends. Your belt never ends. Your belt never ends." },
	[-122] = { name = "Bracers of Null Reference", icon = Q .. "INV_Bracer_01", group = 7, slot = "Wrist",
		type = "Cloth", armor = 0, stats = { "+nil Intellect" }, dur = 25, req = 60,
		flavor = "attempt to index a nil value" },
	[-123] = { name = "Bag of Unused Item IDs", icon = Q .. "INV_Misc_Bag_10", group = 8, slots = "36 Slot Bag",
		flavor = "Every slot holds item #0." },
	[-124] = { name = "Debug Potion of Godmode", icon = Q .. "INV_Potion_54", group = 1, req = 60,
		effect = "Use: You can't die for 10 sec. Your repair bill can." },

	-- Ticketmaster Shrugg's, more
	[-125] = { name = "Scroll of Canned Response", icon = Q .. "INV_Scroll_03", group = 1,
		effect = "Use: Answers any question with \"We're looking into it.\"" },
	[-126] = { name = "Tome of Known Issues", icon = Q .. "INV_Misc_Book_09", group = 10, unique = true,
		flavor = "It's very, very long. Volume one of many." },
	[-127] = { name = "Leggings of Patience", icon = Q .. "INV_Pants_01", group = 7, slot = "Legs",
		type = "Cloth", armor = 80, stats = { "+30 Spirit", "+999 Patience" }, dur = 65, req = 60,
		effect = "Equip: Time spent in a queue feels 5% shorter." },
	[-128] = { name = "Hold Music Ale", icon = Q .. "INV_Drink_05", group = 1,
		effect = "Use: Restores 0 mana over 45 min while a short song loops." },
	[-129] = { name = "Key to the Ticket Queue", icon = Q .. "INV_Misc_Key_14", group = 10, unique = true,
		flavor = "It opens nothing. The queue opens you." },
	[-130] = { name = "Coin of Compensation", icon = Q .. "INV_Misc_Coin_01", group = 10,
		flavor = "Sorry for the inconvenience." },

	-- Captain Nobody's, more
	[-131] = { name = "Spyglass of Distant Shores", icon = Q .. "INV_Misc_Spyglass_03", group = 10, unique = true,
		effect = "Use: Lets you see the mainland. It's very far away." },
	[-132] = { name = "Catch of the Day (Yesterday's)", icon = Q .. "INV_Misc_Fish_02", group = 1,
		effect = "Use: Restores 1 health. Smells like it." },
	[-133] = { name = "Pearl of the Unsailed Sea", icon = Q .. "INV_Misc_Gem_Pearl_04", group = 3,
		flavor = "From a clam that had never seen a boat either." },
	[-134] = { name = "Ship in a Bottle (Empty)", icon = Q .. "INV_Misc_Toy_01", group = 10,
		flavor = "The ship left. Like all the others." },
	[-135] = { name = "Life Jacket of Optimism", icon = Q .. "INV_Chest_Plate06", group = 7, slot = "Chest",
		type = "Leather", armor = 210, stats = { "+20 Stamina", "+40 Buoyancy" }, dur = 85, req = 50,
		effect = "Equip: You float. Towards nothing in particular." },
	-- Chicken Pantz's: birdfeed, and only birdfeed
	[-138] = { name = "Birdfeed", icon = Q .. "INV_Misc_Bag_07", group = 1, effect = "Use: Feed a bird." },
	[-139] = { name = "Premium Birdfeed", icon = Q .. "INV_Misc_Bag_07", group = 1,
		effect = "Use: Feed a bird. It notices the difference." },
	[-140] = { name = "Birdfeed (Family Size)", icon = Q .. "INV_Misc_Bag_10", group = 1,
		effect = "Use: Feed a lot of birds." },
	[-141] = { name = "Organic Free-Range Birdfeed", icon = Q .. "INV_Misc_Flower_02", group = 1,
		flavor = "The seeds were allowed to roam." },
	[-142] = { name = "Birdfeed, Lightly Used", icon = Q .. "INV_Misc_Food_14", group = 1,
		flavor = "Don't ask." },
	[-136] = { name = "Message in a Bottle", icon = Q .. "INV_Potion_31", group = 10, unique = true,
		flavor = "Help. Stuck on GM Island. Send boats. Send GMs. Send anything." },
}
for id, it in pairs(FAKE) do it.id, it.quality = id, 5 end
ns.FakeItems = FAKE

--- one of these laid out on GameTooltip as the game lays out an item's (its owner already set)
function ns.FakeItemTooltip(id)
	local it = FAKE[id]
	if not it then return end
	local W = 1
	GameTooltip:AddLine(it.name, 1, 0.5, 0)
	GameTooltip:AddLine("Binds when picked up", W, W, W)
	if it.unique then GameTooltip:AddLine("Unique", W, W, W) end
	if it.slot then GameTooltip:AddDoubleLine(it.slot, it.type or "", W, W, W, W, W, W) end
	if it.dmg then
		GameTooltip:AddDoubleLine(it.dmg .. " Damage", "Speed " .. it.speed, W, W, W, W, W, W)
		GameTooltip:AddLine(it.dps, W, W, W)
	end
	if it.armor then GameTooltip:AddLine(it.armor .. " Armor", W, W, W) end
	for _, s in ipairs(it.stats or {}) do GameTooltip:AddLine(s, W, W, W) end
	if it.slots then GameTooltip:AddLine(it.slots, W, W, W) end
	if it.dur then GameTooltip:AddLine(("Durability %d / %d"):format(it.dur, it.dur), W, W, W) end
	if it.req then GameTooltip:AddLine("Requires Level " .. it.req, W, W, W) end
	if it.effect then GameTooltip:AddLine(it.effect, 0.12, 1, 0, true) end
	if it.flavor then GameTooltip:AddLine('"' .. it.flavor .. '"', 1, 0.82, 0, true) end
	GameTooltip:AddLine("Sell Price: 99,999 |TInterface\\MoneyFrame\\UI-GoldIcon:0|t", W, W, W)
end

-- its vendors: where they stand on the art (0..1 of it), and what they sell (by kind, as a real
-- vendor's wares are)
local GREY, RED, GOLDEN = { 0.6, 0.6, 0.6 }, { 1, 0.25, 0.25 }, { 1, 0.82, 0 }
-- (a line of an NPC's tooltip. It hides ns.L from here on: GM Island stays in English)
local function L(text, c) c = c or { 1, 1, 1 } return { text, c[1], c[2], c[3] } end

-- its people (and a mailbox and a sign), where they stand on the art (0..1 of it): vendors with
-- what they sell, the rest with what they've to say. kind: their look, as a real marker's
local GM_NPCS = {
	{ id = -1, x = 0.494, y = 0.456, name = "Gamemaster Grizzlebeard", sub = "Legendary Goods", kind = "VENDOR",
		wares = { -101, -102, -103, -113, -114, -115, -116, -117, -118 } },
	{ id = -2, x = 0.481, y = 0.186, name = "Quartermaster Null", sub = "Debug Supplies", kind = "VENDOR",
		wares = { -104, -105, -119, -120, -121, -122, -123, -124, -106 } },
	{ id = -3, x = 0.865, y = 0.61, name = "Ticketmaster Shrugg", sub = "Petitions & Patience", kind = "VENDOR",
		wares = { -107, -108, -109, -125, -126, -127, -128, -129, -130 } },
	{ id = -4, x = 0.505, y = 0.815, name = "Captain Nobody", sub = "Boats (None)", kind = "VENDOR",
		wares = { -110, -111, -112, -131, -132, -133, -134, -135, -136 } },
	{ id = -5, x = 0.33, y = 0.47, name = "Gamemaster Sleepytime", sub = "On Break",
		lines = { L("Zzz... Your ticket has been escalated to a pillow.", GREY) } },
	{ id = -6, x = 0.67, y = 0.485, name = "Senior GM Outtalunch", sub = "Back in 5",
		lines = { L("Has been back in 5 since patch 1.1.", GREY) } },
	{ id = -7, x = 0.43, y = 0.705, name = "Test Dummy", sub = "Do Not Kill",
		lines = { L("Level ??"), L("Health: 1 / 1"), L("Please don't.", GREY) } },
	{ id = -8, x = 0.22, y = 0.475, name = "Unnamed NPC #2,107",
		lines = { L("(Someone forgot to fill this in.)", GREY) } },
	{ id = -9, x = 0.56, y = 0.6, name = "Vaultkeeper Empty", sub = "Banker: Closed for Maintenance", kind = "BANKER",
		lines = { L("The vault is empty. It was always empty.", GREY) } },
	{ id = -10, x = 0.27, y = 0.31, name = "Innkeeper Nowhere", sub = "Innkeeper", kind = "INNKEEPER",
		lines = { L("Set your hearthstone here?"), L("Your hearthstone does not recognise this location.", RED) } },
	{ id = -11, x = 0.755, y = 0.4, name = "Wingless Wendell", sub = "Flight Master (Grounded)", kind = "FLIGHT_MASTER",
		flightSelf = true, lines = { L("No flight paths. There never were.", GREY) } },
	{ id = -12, x = 0.31, y = 0.345, name = "Mailbox", label = "Mailbox (full: 4,812 unread petitions)", kind = "MAILBOX",
		obj = true },
	{ id = -13, x = 0.505, y = 0.877, name = "Sign", label = "Sign", kind = "SIGN", obj = true,
		lines = { L('"Do not feed the GMs."', GOLDEN) } },
	{ id = -14, x = 0.58, y = 0.685, name = "Grandmaster Ultimus", sub = "Grandmaster Trainer", kind = "PROFESSION",
		lines = { L("Teaches:", GOLDEN), L("  Legendary Everything (Rank 1)  |cffff2020Requires Level 60, a GM badge|r"),
			L("  Infinite Gold (Rank 1)  |cffff2020Requires Level 60, an open ticket|r"),
			L("  Flying in Azeroth  |cffff2020Requires Level 60, an expansion|r") } },
	{ id = -15, x = 0.44, y = 0.6, name = "Junior GM Pemberton", sub = "Trainee", kind = "QUEST",
		quests = { "Escalate the Ticket" },
		after = { L("  Find a GM who is awake: 0/1"), L("  Reward: a reply, eventually", GREY) } },
	{ id = -17, x = 0.7, y = 0.56, name = "Chicken Pantz", sub = "Birdfeed", kind = "VENDOR",
		wares = { -138, -139, -140, -141, -142 } },
	-- the sword from South Park's "Make Love, Not Warcraft": too powerful, so they took it out
	{ id = -16, x = 0.42, y = 0.27, name = "Lead Designer Truthkeeper", sub = "Keeper of the Sword", kind = "QUEST",
		legendary = true,
		quests = { "The Sword of a Thousand Truths" },
		after = { L("  A legendary quest", { 1, 0.5, 0 }),
			L("  Boars slain in Elwynn Forest: 0/65,000,000"),
			L("  The player who cannot be killed defeated: 0/1"),
			L("  Reward: |cffff8000[Sword of a Thousand Truths]|r"),
			L('  "It was too powerful. We had to take it out of the game."', GOLDEN) } },
}
local GM_BY_ID = {}
for _, v in ipairs(GM_NPCS) do GM_BY_ID[v.id] = v end
ns.FakeWares = {}
for _, v in ipairs(GM_NPCS) do
	if v.wares then
	local list = {}
	for _, id in ipairs(v.wares) do list[#list + 1] = FAKE[id] end
	table.sort(list, function(a, b)
		if a.group ~= b.group then return a.group < b.group end
		return a.name < b.name
	end)
	ns.FakeWares[v.id] = list
	end
end

-- The island is part of the map, not a marker over it: it's on the map's canvas (what zooms), sized
-- in the map's own terms, so it grows and shrinks with the map as a real island does. Where it is
-- on the map showing (a continent's, a zone's, the world's; OpenMap's stitched map) is worked out
-- again when that changes. Its vendors and name stay a readable size whatever the zoom.
local ISLAND_FRAC = 0.045        -- how wide its picture is: this much of its continent's map
local islandAt                   -- { ui, x, y }: where it is (on a continent's map, 0..1)
local islandKey                  -- what it was last placed for (the map, the canvas's size and zoom)

-- a point of map ui (0..1) on the map showing: x, y (0..1, and past it), or nil where it can't be
-- (another continent's map)
function ToShownMap(ui, cx, cy)
	local host = WorldMapFrame:GetMapID()
	if not host then return end
	local api = OpenMapAPI
	if api and api.IsStitched and api.IsStitched() then
		local u, v = api.WorldFromMap(ui, cx, cy)
		if u then return api.MapFromWorld(host, u, v) end
		return
	end
	if not (HBD and HBD.GetWorldCoordinatesFromZone) then return end
	local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(cx, cy, ui)
	if not wx then return end
	return HBD:GetZoneCoordinatesFromWorldInstance(wx, wy, inst, host, true)
end

-- a point of the island's continent map (0..1) on the map showing
local function OnShownMap(cx, cy) return ToShownMap(islandAt.ui, cx, cy) end

--- a point of map ui (0..1) on the map shown (0..1), or nil where it can't be
function Pins.ToShownMap(ui, x, y) return ToShownMap(ui, x, y) end

--------------------------------------------------------------------------------
-- An item's areas (where it drops), filled and outlined as the game draws a quest's area: on
-- the world map's canvas (over its art, OpenMap's too, under the markers) and on the minimap.
-- Their outlines (Areas.lua) are in their zone's terms. Hover one on the world map and click it
-- to pin it: that spot stays (on the map and the minimap, the map closed or not, after a
-- reload too) until the X on its bar on the map
--------------------------------------------------------------------------------

-- (the translations again: GM Island's line maker took the name L above)
local L = ns.L

local AREA_FILL = { 1, 0.82, 0.1, 0.22 }
local AREA_EDGE = { 1, 0.82, 0.1, 0.9 }
local BEST_FILL = { 0.64, 0.21, 0.93, 0.3 }   -- (the best spot: an epic item's purple)
local BEST_EDGE = { 0.75, 0.4, 1, 0.95 }
local HOVER_EDGE = { 1, 1, 1, 1 }             -- (under the cursor: click to pin it)
local AREA_EDGE_PX = 2
local MINI_EDGE_PX = 1.5
local MINI_EVERY = 0.03                       -- seconds between the minimap's redraws (as you move)
local CLICK_SLOP = 6                          -- px the cursor may move in a click (more: the map dragged)
local UL, LL = _G.UPPER_LEFT_VERTEX or 1, _G.LOWER_LEFT_VERTEX or 2
local UR, LR = _G.UPPER_RIGHT_VERTEX or 3, _G.LOWER_RIGHT_VERTEX or 4
local CAN_FILL = (function()
	local probe = UIParent:CreateTexture()
	local ok = probe.SetVertexOffset ~= nil   -- (no way to bend a texture: the outlines alone)
	probe:Hide()
	return ok
end)()

local searchAreas             -- the search's areas (gone with it)
local spot                    -- the pinned one (ns.db.spot)
local hovered                 -- the area under the cursor on the world map
local areaF, areaKey          -- the world map's layer, and what it was last drawn for
local drawn = {}              -- what's on the world map: { a, px, py, l, t, r, b }, ...
local mapPool = { tris = {}, lines = {} }
local miniPool = { tris = {}, lines = {}, edge = { 0, 0, 0, 0.85 } }   -- (edge: the dark edge under a route's current step; drawn: the lines last made)
local spotBar, spotIcon       -- the pinned spot's bar on the map, and its minimap marker
local miniDirty = true
local MINI_PATH_PX = 2.5
local miniPaths   -- lines on the minimap (a route, a farming loop): { { w = { { x, y, inst } }, closed, col } }

-- a triangle (units down and right of rel's point): a texture's four corners moved onto its
-- three (two on one)
local function Triangle(t, rel, point, ax, ay, bx, by, cx, cy)
	local l, r = math.min(ax, bx, cx), math.max(ax, bx, cx)
	local top, bottom = math.min(ay, by, cy), math.max(ay, by, cy)
	if r - l < 0.5 then r = l + 0.5 end
	if bottom - top < 0.5 then bottom = top + 0.5 end
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", rel, point, l, -top)
	t:SetSize(r - l, bottom - top)
	-- (each corner's offset from where it'd be: right, and up)
	t:SetVertexOffset(UL, ax - l, top - ay)
	t:SetVertexOffset(UR, bx - r, top - by)
	t:SetVertexOffset(LL, cx - l, bottom - cy)
	t:SetVertexOffset(LR, cx - r, bottom - cy)
end

local function PoolTri(P, f, n, col)
	local tex = P.tris[n]
	if not tex then
		tex = f:CreateTexture(nil, "ARTWORK")
		P.tris[n] = tex
	end
	tex:SetColorTexture(col[1], col[2], col[3], col[4])
	tex:Show()
	return tex
end

local function PoolLine(P, f, n, col, thick, under)
	local line = P.lines[n]
	if not line then
		line = f:CreateLine(nil, "OVERLAY")
		P.lines[n] = line
	end
	line:SetDrawLayer(under and "ARTWORK" or "OVERLAY")   -- (under: a line's dark edge, beneath the lines)
	line:SetColorTexture(col[1], col[2], col[3], col[4])
	line:SetThickness(thick)
	line:Show()
	return line
end

local function PoolTrim(P, nT, nL)
	for i = nT + 1, #P.tris do P.tris[i]:Hide() end
	for i = nL + 1, #P.lines do P.lines[i]:Hide() end
end

-- what to draw: the search's areas, and the pinned spot (once: it may be one of them)
local function Shown()
	local list, pinnedIn = {}, false
	for _, a in ipairs(searchAreas or {}) do
		list[#list + 1] = a
		if spot and a.key == spot.key then pinnedIn = true end
	end
	if spot and not pinnedIn then list[#list + 1] = spot end
	return list
end

local function IsPinned(a) return spot ~= nil and a.key == spot.key end

local function Colours(a)
	local fill, edge = a.best and BEST_FILL or AREA_FILL, a.best and BEST_EDGE or AREA_EDGE
	if a == hovered then edge = HOVER_EDGE end
	return fill, edge
end

-- (a point inside an area: in any of its loops)
local function InLoops(x, y, d)
	if x < d.l or x > d.r or y < d.t or y > d.b then return false end
	for _, loop in ipairs(d.a.loops) do
		local first, count = loop[1], loop[2]
		local inside, j = false, first + count - 1
		for i = first, first + count - 1 do
			local xi, yi, xj, yj = d.px[i], d.py[i], d.px[j], d.py[j]
			if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
			j = i
		end
		if inside then return true end
	end
	return false
end

local function PlaceArea(force)
	local f = areaF
	if not f then return end
	local list = Shown()
	local canvas = f:GetParent()
	local w, h, scale = canvas:GetWidth(), canvas:GetHeight(), canvas:GetScale()
	local shown = WorldMapFrame:GetMapID()
	local key = ("%s:%d:%d:%.4f"):format(tostring(shown), w, h, scale)
	if key == areaKey and not force then return end
	areaKey = key
	wipe(drawn)
	if not (shown and w > 0 and #list > 0) then f:Hide() PoolTrim(mapPool, 0, 0) return end
	local nT, nL = 0, 0
	local thick = AREA_EDGE_PX / math.max(scale, 0.01)
	for _, a in ipairs(list) do
		-- (its zone's map onto the one shown: a scale and a shift, from two of its points. Shown
		-- on any map of its continent: its zone's, the continent's, the next zone's at its edge)
		local x0, y0 = ToShownMap(a.ui, 0, 0)
		local x1, y1 = ToShownMap(a.ui, 1, 1)
		if x0 and x1 then
			local fill, edge = Colours(a)
			local sx, sy = (x1 - x0) * w / 100, (y1 - y0) * h / 100
			local ox, oy = x0 * w, y0 * h
			local V = a.verts
			local px, py = {}, {}
			local l, t, r, b = math.huge, math.huge, -math.huge, -math.huge
			for i = 1, #V / 2 do
				local x, y = ox + V[2 * i - 1] * sx, oy + V[2 * i] * sy
				px[i], py[i] = x, y
				l, t, r, b = math.min(l, x), math.min(t, y), math.max(r, x), math.max(b, y)
			end
			drawn[#drawn + 1] = { a = a, px = px, py = py, l = l, t = t, r = r, b = b }
			if CAN_FILL then
				for _, tr in ipairs(a.tris) do
					nT = nT + 1
					Triangle(PoolTri(mapPool, f, nT, fill), f, "TOPLEFT",
						px[tr[1]], py[tr[1]], px[tr[2]], py[tr[2]], px[tr[3]], py[tr[3]])
				end
			end
			if f.CreateLine then
				local tk = (IsPinned(a) or a == hovered) and thick * 1.5 or thick
				for _, loop in ipairs(a.loops) do
					local first, count = loop[1], loop[2]
					for k = 0, count - 1 do
						local i, j = first + k, first + (k + 1) % count
						nL = nL + 1
						local line = PoolLine(mapPool, f, nL, edge, tk)
						line:SetStartPoint("TOPLEFT", f, px[i], -py[i])
						line:SetEndPoint("TOPLEFT", f, px[j], -py[j])
					end
				end
			end
		end
	end
	PoolTrim(mapPool, nT, nL)
	f:SetShown(nT + nL > 0)
end

local function RaiseArea()
	local view = WorldMapFrame.ScrollContainer
	if not (areaF and view) then return end
	local level = math.max(1, TopLevel(view) - 5)   -- (under GM Island, under the markers)
	if areaF:GetFrameLevel() ~= level then areaF:SetFrameLevel(level) end
end

--------------------------------------------------------------------------------
-- The minimap: the same areas around you, turned with it when it turns, cut at its edge
--------------------------------------------------------------------------------

local MM = (HBDPins and HBDPins.Minimap) or Minimap
local mini = CreateFrame("Frame", nil, MM)
mini:SetAllPoints(MM)
mini:SetFrameLevel(MM:GetFrameLevel() + 1)   -- (over the map, under its icons)
mini:EnableMouse(false)

local clipCache = {}
-- the minimap's edge, as a convex shape to cut at (units right and up of its middle)
local function ClipShape(hw, hh)
	local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
	local key = ("%s:%.1f:%.1f"):format(tostring(square), hw, hh)
	if clipCache.key == key then return clipCache.shape end
	local shape = {}
	if square then
		shape = { { -hw, -hh }, { hw, -hh }, { hw, hh }, { -hw, hh } }
	else
		local n, rx, ry = 40, hw * 0.98, hh * 0.98
		for i = 0, n - 1 do
			local t = i / n * 2 * math.pi
			shape[#shape + 1] = { rx * math.cos(t), ry * math.sin(t) }
		end
	end
	clipCache.key, clipCache.shape = key, shape
	return shape
end

-- a polygon cut to the inside of a convex shape (Sutherland-Hodgman); both counter-clockwise
local function ClipPolygon(poly, shape)
	local out = poly
	for i = 1, #shape do
		local p, q = shape[i], shape[i % #shape + 1]
		local ex, ey = q[1] - p[1], q[2] - p[2]
		local input = out
		out = {}
		if #input == 0 then return out end
		local function Side(v) return ex * (v[2] - p[2]) - ey * (v[1] - p[1]) end
		local prev = input[#input]
		local sp = Side(prev)
		for _, cur in ipairs(input) do
			local sc = Side(cur)
			if sc >= 0 then
				if sp < 0 then
					local t = sp / (sp - sc)
					out[#out + 1] = { prev[1] + t * (cur[1] - prev[1]), prev[2] + t * (cur[2] - prev[2]) }
				end
				out[#out + 1] = cur
			elseif sp >= 0 then
				local t = sp / (sp - sc)
				out[#out + 1] = { prev[1] + t * (cur[1] - prev[1]), prev[2] + t * (cur[2] - prev[2]) }
			end
			prev, sp = cur, sc
		end
	end
	return out
end

-- a line cut to the inside of a convex shape (Cyrus-Beck), or nil when it's all outside
local function ClipSegment(x1, y1, x2, y2, shape)
	local t0, t1, dx, dy = 0, 1, x2 - x1, y2 - y1
	for i = 1, #shape do
		local p, q = shape[i], shape[i % #shape + 1]
		local nx, ny = -(q[2] - p[2]), q[1] - p[1]   -- (inward, the shape counter-clockwise)
		local num = nx * (x1 - p[1]) + ny * (y1 - p[2])
		local den = nx * dx + ny * dy
		if den == 0 then
			if num < 0 then return end
		else
			local t = -num / den
			if den > 0 then t0 = math.max(t0, t) else t1 = math.min(t1, t) end
			if t0 > t1 then return end
		end
	end
	return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end

-- an area's corners in world yards (its zone's map to the world: a scale and a shift). Kept
-- aside, not on the area: the pinned one's saved, and these needn't be
local worldOf = setmetatable({}, { __mode = "k" })
local function WorldOf(a)
	if worldOf[a] then return worldOf[a] end
	if not (HBD and HBD.GetWorldCoordinatesFromZone) then return end
	local x0, y0, inst = HBD:GetWorldCoordinatesFromZone(0, 0, a.ui)
	local x1, y1 = HBD:GetWorldCoordinatesFromZone(1, 1, a.ui)
	if not (x0 and x1) then return end
	local V, wx, wy = a.verts, {}, {}
	for i = 1, #V / 2 do
		wx[i] = x0 + (x1 - x0) * V[2 * i - 1] / 100
		wy[i] = y0 + (y1 - y0) * V[2 * i] / 100
	end
	worldOf[a] = { x = wx, y = wy, inst = inst }
	return worldOf[a]
end

--- lines drawn on the minimap, under its own icons (the herbs and veins it tracks stay in
--- sight): { { pts = { { ui, x, y (0..100) }, ... }, closed = loop?, col = { r, g, b, a } }, ... },
--- or nil. Route.lua's route and farming loop
function Pins.SetMiniPaths(paths)
	miniPaths = nil
	if paths and HBD and HBD.GetWorldCoordinatesFromZone then
		miniPaths = {}
		for _, p in ipairs(paths) do
			-- (you: the path's first so many points are the step you're on, drawn from you)
			local w, you = {}, nil
			for i, pt in ipairs(p.pts) do
				local x, y, inst = HBD:GetWorldCoordinatesFromZone(pt.x / 100, pt.y / 100, pt.ui)
				if x then w[#w + 1] = { x = x, y = y, inst = inst } end
				if p.you and i == p.you and #w > 0 then you = #w end
			end
			if #w > 1 or you then miniPaths[#miniPaths + 1] = { w = w, closed = p.closed, col = p.col, you = you, now = you and p.now } end
		end
		if #miniPaths == 0 then miniPaths = nil end
	end
	miniDirty = true
end

-- the minimap's view: yards from its middle to its edge, and whether it turns with you. Questie's
-- own copy of HereBeDragons says (GetMinimapView); another addon's copy of that library, loaded
-- in its place, doesn't: then the game's word for it, or the sizes each zoom has, indoors and out
-- (as HereBeDragons places its icons by)
Pins.MINI_SIZE = { indoor = { [0] = 300, 240, 180, 120, 80, 50 }, outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 } }
function Pins.MiniView()
	if HBDPins and HBDPins.GetMinimapView then return HBDPins:GetMinimapView() end
	local radius
	if C_Minimap and C_Minimap.GetViewRadius then
		radius = C_Minimap.GetViewRadius()
	else
		local zoom = MM.GetZoom and MM:GetZoom() or 0
		local size = Pins.MINI_SIZE[(IsIndoors and IsIndoors()) and "indoor" or "outdoor"][zoom]
		radius = size and size / 2
	end
	return radius, GetCVar and GetCVar("rotateMinimap") == "1"
end

local miniKey
local function PlaceMini()
	local list = Shown()
	if (#list == 0 and not miniPaths) or not (HBD and HBD.GetPlayerWorldPosition) then
		if mini:IsShown() then PoolTrim(miniPool, 0, 0) mini:Hide() end
		miniKey = nil
		return
	end
	local px, py, pinst = HBD:GetPlayerWorldPosition()
	local radius, rotating = Pins.MiniView()
	local facing = rotating and GetPlayerFacing and GetPlayerFacing()
	if not (px and radius and radius > 0) or (rotating and not facing) then
		PoolTrim(miniPool, 0, 0)
		miniKey = nil
		return
	end
	local hw, hh = MM:GetWidth() / 2, MM:GetHeight() / 2
	local key = ("%.1f:%.1f:%.1f:%.3f:%.1f:%d"):format(px, py, radius, facing or 0, hw, #list)
	if key == miniKey and not miniDirty then return end
	miniKey, miniDirty = key, false
	local shape = ClipShape(hw, hh)
	local s, c = 0, 1
	if rotating then s, c = math.sin(facing), math.cos(facing) end
	local nT, nL = 0, 0
	for _, a in ipairs(list) do
		local wd = WorldOf(a)
		if wd and wd.inst == pinst then
			-- (each corner on the minimap: units right and up of its middle, as HereBeDragons places icons)
			local X, Y, any = {}, {}, false
			for i = 1, #wd.x do
				local dx, dy = px - wd.x[i], py - wd.y[i]
				if rotating then dx, dy = dx * c - dy * s, dx * s + dy * c end
				X[i], Y[i] = dx / radius * hw, -dy / radius * hh
				if not any and math.abs(X[i]) < hw * 3 and math.abs(Y[i]) < hh * 3 then any = true end
			end
			if any then
				local fill, edge = a.best and BEST_FILL or AREA_FILL, a.best and BEST_EDGE or AREA_EDGE
				if CAN_FILL then
					for _, tr in ipairs(a.tris) do
						local i, j, k = tr[1], tr[2], tr[3]
						local poly = { { X[i], Y[i] }, { X[j], Y[j] }, { X[k], Y[k] } }
						-- (counter-clockwise, as the cut wants)
						if (X[j] - X[i]) * (Y[k] - Y[i]) - (Y[j] - Y[i]) * (X[k] - X[i]) < 0 then
							poly[2], poly[3] = poly[3], poly[2]
						end
						local cut = ClipPolygon(poly, shape)
						for m = 2, #cut - 1 do
							nT = nT + 1
							Triangle(PoolTri(miniPool, mini, nT, fill), mini, "CENTER",
								cut[1][1], -cut[1][2], cut[m][1], -cut[m][2], cut[m + 1][1], -cut[m + 1][2])
						end
					end
				end
				if mini.CreateLine then
					for _, loop in ipairs(a.loops) do
						local first, count = loop[1], loop[2]
						for kk = 0, count - 1 do
							local i, j = first + kk, first + (kk + 1) % count
							local x1, y1, x2, y2 = ClipSegment(X[i], Y[i], X[j], Y[j], shape)
							if x1 then
								nL = nL + 1
								local line = PoolLine(miniPool, mini, nL, edge, MINI_EDGE_PX)
								line:SetStartPoint("CENTER", mini, x1, y1)
								line:SetEndPoint("CENTER", mini, x2, y2)
							end
						end
					end
				end
			end
		end
	end
	-- (a route's lines, a farming loop's: thin, over the minimap's ground)
	for _, path in ipairs(miniPaths or {}) do
		local W, n = path.w, #path.w
		local function At(w)
			local dx, dy = px - w.x, py - w.y
			if rotating then dx, dy = dx * c - dy * s, dx * s + dy * c end
			return dx / radius * hw, -dy / radius * hh
		end
		-- (a line of it; the step you're on with a dark edge under it, to show on pale ground)
		local function PathLine(x1, y1, x2, y2, col, edged)
			if edged then
				nL = nL + 1
				local edge = PoolLine(miniPool, mini, nL, miniPool.edge, MINI_PATH_PX + 2.5, true)
				edge:SetStartPoint("CENTER", mini, x1, y1)
				edge:SetEndPoint("CENTER", mini, x2, y2)
			end
			nL = nL + 1
			local line = PoolLine(miniPool, mini, nL, col, edged and MINI_PATH_PX + 0.5 or MINI_PATH_PX)
			line:SetStartPoint("CENTER", mini, x1, y1)
			line:SetEndPoint("CENTER", mini, x2, y2)
		end
		-- (the step you're on: from you to its first point still ahead of you, nearer its end than
		-- you are; those behind you aren't drawn)
		local from = 1
		local E = path.you and W[path.you]
		if E and E.inst == pinst and mini.CreateLine then
			local mine = (px - E.x) ^ 2 + (py - E.y) ^ 2
			from = path.you
			for i = 1, path.you - 1 do
				if (W[i].x - E.x) ^ 2 + (W[i].y - E.y) ^ 2 < mine then from = i break end
			end
			local bx, by = At(W[from])
			local x1, y1, x2, y2 = ClipSegment(0, 0, bx, by, shape)
			if x1 then PathLine(x1, y1, x2, y2, path.now or path.col, path.now) end
		end
		for i = from, path.closed and n or n - 1 do
			local a, b = W[i], W[i % n + 1]
			if a.inst == pinst and b.inst == pinst then
				local ax, ay = At(a)
				local bx, by = At(b)
				local x1, y1, x2, y2 = ClipSegment(ax, ay, bx, by, shape)
				if x1 and mini.CreateLine then
					local now = path.now and i < path.you
					PathLine(x1, y1, x2, y2, now and path.now or path.col, now)
				end
			end
		end
	end
	PoolTrim(miniPool, nT, nL)
	mini:SetShown(nT + nL > 0)
	miniPool.drawn = nL
end

--- "/seek mini": what the minimap's lines are made of just now, said in chat (for when a route's
--- line shows on the world map and not here)
function Pins.MiniDebug()
	local say = ns.Print
	local px, py, pinst
	if HBD and HBD.GetPlayerWorldPosition then px, py, pinst = HBD:GetPlayerWorldPosition() end
	local radius, rotating
	radius, rotating = Pins.MiniView()
	say(("minimap: frame %s, level %s, strata %s, shown %s, size %.0f x %.0f; lines drawn last %s; can draw lines %s"):format(
		tostring(MM and MM.GetName and MM:GetName()), tostring(mini:GetFrameLevel()), tostring(mini:GetFrameStrata()),
		tostring(mini:IsShown()), mini:GetWidth() or 0, mini:GetHeight() or 0, tostring(miniPool.drawn), tostring(mini.CreateLine ~= nil)))
	say(("you: %s, %s on world %s; view radius %s, turning %s; libraries %s / %s"):format(
		px and ("%.0f"):format(px) or "?", py and ("%.0f"):format(py) or "?", tostring(pinst), tostring(radius), tostring(rotating),
		tostring(HBD ~= nil), tostring(HBDPins ~= nil and HBDPins.GetMinimapView ~= nil)))
	if not miniPaths then say("no lines set for the minimap") return end
	for i, path in ipairs(miniPaths) do
		local w = path.w
		local first, last = w[1], w[#w]
		say(("line %d: %d points on world %s, yours for the step %s, closed %s; first %.0f yards off, last %.0f yards off"):format(
			i, #w, tostring(first and first.inst), tostring(path.you), tostring(path.closed),
			(px and first) and math.sqrt((px - first.x) ^ 2 + (py - first.y) ^ 2) or -1,
			(px and last) and math.sqrt((px - last.x) ^ 2 + (py - last.y) ^ 2) or -1))
	end
end

--------------------------------------------------------------------------------
-- The pinned spot: its bar on the map (click: its zone; X: unpin) and its minimap marker
-- (on the minimap's edge, pointing the way, when it's further off)
--------------------------------------------------------------------------------

local SPOT_REF = "MapSeekSpot"

local function SpotText()
	if not spot then return "" end
	local what = spot.name or "?"
	if spot.label and spot.label ~= "" then what = what .. " (" .. spot.label .. ")" end
	return L["Pinned: %s"]:format(what .. ", " .. (ns.ZoneName(spot.ui) or "?"))
end

local function UpdateSpotBar()
	if not spotBar then return end
	if not spot then spotBar:Hide() return end
	spotBar.icon:SetTexture(spot.icon or "Interface\\Icons\\INV_Misc_Bag_10")
	spotBar.text:SetText(SpotText())
	spotBar:SetWidth(spotBar.text:GetStringWidth() + 56)
	spotBar:Show()
end

local function MakeSpotBar()
	local parent = Holder()
	if spotBar or not parent then return end
	local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	b:SetHeight(24)
	b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 10, 10)
	b:SetFrameLevel(parent:GetFrameLevel() + 30)
	if b.SetBackdrop then
		b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		b:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
		b:SetBackdropBorderColor(BEST_EDGE[1], BEST_EDGE[2], BEST_EDGE[3], 0.9)
	end
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(16, 16)
	icon:SetPoint("LEFT", 5, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.icon = icon
	local text = ns.Text(b, "GameFontHighlightSmall")
	text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	if ns.SkinText then ns.SkinText(text) end
	b.text = text
	local x = CreateFrame("Button", nil, b)
	x:SetSize(16, 16)
	x:SetPoint("RIGHT", -4, 0)
	local xt = x:CreateTexture(nil, "ARTWORK")
	xt:SetAllPoints()
	xt:SetTexture("Interface\\Buttons\\UI-StopButton")
	xt:SetAlpha(0.7)
	x:SetScript("OnEnter", function(self)
		xt:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Unpin"], 1, 1, 1)
		GameTooltip:Show()
	end)
	x:SetScript("OnLeave", function() xt:SetAlpha(0.7) GameTooltip:Hide() end)
	x:SetScript("OnClick", function() Pins.Unpin() end)
	-- (EUI: its flat panel and its close glyph)
	if ns.SkinPanel then ns.SkinPanel(b) end
	if ns.SkinClose then ns.SkinClose(x, xt) end
	b:SetScript("OnClick", function()
		if spot and WorldMapFrame:GetMapID() ~= spot.ui then WorldMapFrame:SetMapID(spot.ui) end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(SpotText(), 1, 0.82, 0.1, true)
		GameTooltip:AddLine(L["On the map and minimap until you unpin it, the map closed or not."], 1, 1, 1, true)
		GameTooltip:AddLine(L["Click to show it on the map"], 0.5, 1, 0.5)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	spotBar = b
end

local function UpdateSpotIcon()
	if not HBDPins then return end
	HBDPins:RemoveAllMinimapIcons(SPOT_REF)
	if not (spot and spot.mid) then return end
	if not spotIcon then
		spotIcon = CreateFrame("Frame", nil, MM)
		spotIcon:SetSize(14, 14)
		local t = spotIcon:CreateTexture(nil, "OVERLAY")
		t:SetAllPoints()
		t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		spotIcon.tex = t
		spotIcon:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(SpotText(), 1, 0.82, 0.1, true)
			GameTooltip:Show()
		end)
		spotIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	spotIcon.tex:SetTexture(spot.icon or "Interface\\Icons\\INV_Misc_Bag_10")
	-- (on the minimap's edge when it's further off: which way to go)
	HBDPins:AddMinimapIconMap(SPOT_REF, spotIcon, spot.ui, spot.mid[1] / 100, spot.mid[2] / 100, false, true)
end

local function Redraw()
	miniDirty = true
	if areaF then PlaceArea(true) end
	PlaceMini()
end

--- pin an area (one of the search's): kept on the map and minimap until unpinned
function Pins.PinSpot(a)
	if not a then return end
	spot = { key = a.key, ui = a.ui, verts = a.verts, tris = a.tris, loops = a.loops, best = a.best,
		name = a.name, label = a.label, icon = a.icon, mid = a.mid }
	ns.db.spot = spot
	MakeSpotBar()
	UpdateSpotBar()
	UpdateSpotIcon()
	Redraw()
	ns.Print(L["%s; the X on the map unpins it."]:format(SpotText()))
end

function Pins.Unpin()
	spot = nil
	if ns.db then ns.db.spot = nil end
	if HBDPins then HBDPins:RemoveAllMinimapIcons(SPOT_REF) end
	UpdateSpotBar()
	Redraw()
end

--------------------------------------------------------------------------------
-- The world map's layer: made when first needed; while the map's up it's kept placed, raised,
-- and watched for the cursor over an area (its tooltip; a click pins it)
--------------------------------------------------------------------------------

local function ShowHover(a)
	if a then
		GameTooltip:SetOwner(areaF, "ANCHOR_CURSOR")
		GameTooltip:AddLine(a.name or "?", 1, 0.82, 0.1)
		if a.label and a.label ~= "" then GameTooltip:AddLine(a.label, 1, 1, 1, true) end
		if IsPinned(a) then
			GameTooltip:AddLine(L["Pinned: the X on the map unpins it."], 0.75, 0.4, 1, true)
		else
			GameTooltip:AddLine(L["Click to pin this spot: it stays on the map and minimap after you close the map."], 0.5, 1, 0.5, true)
		end
		GameTooltip:Show()
	elseif GameTooltip:IsOwned(areaF) then
		GameTooltip:Hide()
	end
end

local function EnsureArea()
	local view = WorldMapFrame and WorldMapFrame.ScrollContainer
	local canvas = view and view.Child
	if areaF or not canvas then return areaF end
	local f = CreateFrame("Frame", nil, canvas)
	f:SetAllPoints(canvas)
	f:EnableMouse(false)
	f:Hide()
	areaF = f
	local watch = CreateFrame("Frame", nil, WorldMapFrame)
	local since = 0
	watch:SetScript("OnUpdate", function(_, elapsed)
		if not (searchAreas or spot) then
			if hovered then hovered = nil ShowHover(nil) end
			return
		end
		PlaceArea()
		since = since + elapsed
		if since > 0.5 then since = 0 RaiseArea() end
		-- (the cursor over an area: lit, with its tooltip; not over a marker's, which has its own)
		local over
		if view:IsMouseOver() and view.GetNormalizedCursorPosition then
			local nx, ny = view:GetNormalizedCursorPosition()
			if nx then
				local cx, cy = nx * canvas:GetWidth(), ny * canvas:GetHeight()
				for i = #drawn, 1, -1 do
					if InLoops(cx, cy, drawn[i]) then over = drawn[i].a break end
				end
			end
		end
		if over and GameTooltip:IsShown() and not GameTooltip:IsOwned(areaF) then over = nil end
		if over ~= hovered then
			hovered = over
			PlaceArea(true)
			ShowHover(over)
		end
	end)
	-- a click on an area (not a drag of the map): pin it
	local downX, downY
	view:HookScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then downX, downY = GetCursorPosition() end
	end)
	view:HookScript("OnMouseUp", function(_, button)
		if button ~= "LeftButton" or not (hovered and downX) then return end
		local x, y = GetCursorPosition()
		local s = view:GetEffectiveScale()
		if math.abs(x - downX) / s <= CLICK_SLOP and math.abs(y - downY) / s <= CLICK_SLOP and not IsPinned(hovered) then
			Pins.PinSpot(hovered)
			ShowHover(hovered)
		end
		downX = nil
	end)
	return areaF
end

--- draw an item's areas (Areas.Outline's: a list) on the map and minimap, until the search is cleared
function Pins.ShowArea(areas)
	local list = {}
	for _, a in ipairs(areas or {}) do
		if a.verts and #a.verts >= 6 then list[#list + 1] = a end
	end
	if #list == 0 then return end
	searchAreas = list
	if EnsureArea() then
		RaiseArea()
	end
	Redraw()
end

local function HideArea()
	searchAreas, areaKey, hovered = nil, nil, nil
	if areaF and GameTooltip:IsOwned(areaF) then GameTooltip:Hide() end
	Redraw()
end

-- the minimap kept up to date as you move; and the pinned spot from last time, once it's known
local miniWatch = CreateFrame("Frame")
local miniSince = 0
local stillX, stillY, stillF, stillZ, stillA, stillS, stillP, stillShown, stillN = nil, nil, nil, nil, nil, nil, nil, nil, 0
miniWatch:SetScript("OnUpdate", function(_, elapsed)
	miniSince = miniSince + elapsed
	if miniSince < MINI_EVERY then return end
	miniSince = 0
	if ns.db and ns.db.spot ~= spot and spot == nil and ns.db.spot and ns.db.spot.verts then
		spot = ns.db.spot
		UpdateSpotIcon()
		miniDirty = true
	end
	if spot and WorldMapFrame and WorldMapFrame:IsShown() then
		if not areaF and EnsureArea() then RaiseArea() PlaceArea(true) end
		if not spotBar then MakeSpotBar() UpdateSpotBar() end
	end
	if searchAreas or spot or miniPaths or mini:IsShown() then
		-- (stood still, the same things to draw: as it is)
		local px, py = nil, nil
		if HBD and HBD.GetPlayerWorldPosition then px, py = HBD:GetPlayerWorldPosition() end
		local facing = GetPlayerFacing and GetPlayerFacing() or 0
		local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
		if px and px == stillX and py == stillY and facing == stillF and zoom == stillZ and searchAreas == stillA
			and spot == stillS and miniPaths == stillP and not miniDirty and mini:IsShown() == stillShown then
			stillN = stillN + 1
			if stillN < 30 then return end   -- (but a look now and then: the minimap's size, indoors or out)
		end
		stillX, stillY, stillF, stillZ, stillA, stillS, stillP, stillN = px, py, facing, zoom, searchAreas, spot, miniPaths, 0
		PlaceMini()
		stillShown = mini:IsShown()
	end
end)

-- the island over everything on the map, as the markers' layer is (OpenMap's art and icons, Questie's),
-- just under that layer, so a marker still shows over it; its people just over it. (OpenMap builds
-- its layers once the map's open: looked at again now and then)
local function RaiseIsland()
	local f = island
	local view = WorldMapFrame.ScrollContainer
	if not (f and view) then return end
	local level = TopLevel(view) - 3
	if f:GetFrameLevel() ~= level then
		f:SetFrameLevel(level)
		for _, b in ipairs(f.vendors) do b:SetFrameLevel(level + 1) end
	end
end

local function PlaceIsland(force)
	local f = island
	if force then RaiseIsland() end
	local canvas = f:GetParent()
	local w, h, scale = canvas:GetWidth(), canvas:GetHeight(), canvas:GetScale()
	local key = ("%s:%d:%d:%.4f"):format(tostring(WorldMapFrame:GetMapID()), w, h, scale)
	if key == islandKey and not force then return end
	islandKey = key
	local mx, my = OnShownMap(islandAt.x, islandAt.y)
	local ex = OnShownMap(islandAt.x + ISLAND_FRAC, islandAt.y)
	if not (mx and ex and w > 0) then f:Hide() return end
	local size = math.abs(ex - mx) * w
	if size < 2 then f:Hide() return end
	f:ClearAllPoints()
	f:SetPoint("CENTER", canvas, "TOPLEFT", mx * w, -my * h)
	f:SetSize(size, size)
	-- (its vendors and name: on their spots, but not scaled with the map)
	local inv = 1 / math.max(scale, 0.01)
	local roomy = size * scale >= 90   -- (too small on screen to tell them apart: the island only)
	for _, b in ipairs(f.vendors) do
		b:SetShown(roomy)
		b:SetScale(inv)
		b:ClearAllPoints()
		b:SetPoint("CENTER", f, "TOPLEFT", b.vendor.x * size / inv, -b.vendor.y * size / inv)
	end
	f.label:SetScale(inv)
	f.label:ClearAllPoints()
	f.label:SetPoint("TOP", f, "BOTTOM", 0, size * 0.08 / inv)
	f:Show()
end

function Pins.ShowIsland(ui, x, y)
	local canvas = WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
	if not canvas then return end
	islandAt = { ui = ui, x = x, y = y }
	if not island then
		local f = CreateFrame("Frame", nil, canvas)
		f:Hide()
		-- (over the map's art, OpenMap's too: RaiseIsland)
		local art = f:CreateTexture(nil, "ARTWORK")
		art:SetAllPoints()
		art:SetTexture(ISLAND)
		-- its name, lettered as the map letters a place's: the game's gold, outlined
		local label = ns.Text(f, "GameFontNormal")
		ns.Outline(label, 13)
		label:SetTextColor(1, 0.82, 0)
		label:SetShadowColor(0, 0, 0, 1)
		label:SetShadowOffset(1, -1)
		label:SetText("GM Island")
		f.label = label
		-- its vendors
		f.vendors = {}
		for _, v in ipairs(GM_NPCS) do
			local b = CreateFrame("Button", nil, f)
			b:SetSize(14, 14)
			local ic = b:CreateTexture(nil, "ARTWORK")
			ic:SetAllPoints()
			-- (its look, as a real marker's: a service's icon, or the gold dot of an NPC with none)
			if v.kind and LOOKS[v.kind] then
				ns.SetLook(ic, LOOKS[v.kind])
				-- (a legendary quest's "!": in the legendary orange)
				if v.legendary then
					ic:SetDesaturated(true)
					ic:SetVertexColor(1, 0.5, 0)
				end
			else
				ic:SetTexture(DOT)
				ic:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
			end
			b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			b.vendor = v
			-- (a vendor's marker as any other: its tooltip, right-click for the card of its wares,
			-- shift-click to share it, click for a waypoint)
			b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			b:SetScript("OnEnter", OnEnter)
			b:SetScript("OnLeave", OnLeave)
			b:SetScript("OnClick", OnClick)
			f.vendors[#f.vendors + 1] = b
		end
		-- (placed again whenever the map, its size or its zoom changes: a frame that runs only while
		-- the map's up)
		local watch = CreateFrame("Frame", nil, WorldMapFrame)
		local since = 0
		watch:SetScript("OnUpdate", function(_, elapsed)
			if not f.on then return end
			PlaceIsland()
			since = since + elapsed
			if since > 0.5 then since = 0 RaiseIsland() end
		end)
		island = f
	end
	-- (each vendor as a marker's details: where it is, on the island's continent, and the island's name)
	for _, b in ipairs(island.vendors) do
		local v = b.vendor
		b.qms = { id = v.id, name = v.name, sub = v.sub, kind = v.kind, label = v.label, lines = v.lines,
			quests = v.quests, after = v.after,
			obj = v.obj, flightSelf = v.flightSelf, place = "GM Island", island = true, ui = ui,
			x = (x + (v.x - 0.5) * ISLAND_FRAC) * 100, y = (y + (v.y - 0.5) * ISLAND_FRAC) * 100 }
	end
	island.on = true
	PlaceIsland(true)
end

--- where one of the island's people stands (on its continent's map, 0..1), once it's shown; and their name
function Pins.IslandNpc(id)
	local v = GM_BY_ID[id]
	if not v then return end
	if not islandAt then return nil, nil, nil, v.name end
	return islandAt.ui, islandAt.x + (v.x - 0.5) * ISLAND_FRAC, islandAt.y + (v.y - 0.5) * ISLAND_FRAC, v.name
end

--- one of the island's wares that a search names ("ban hammer"): the vendor's id and the item; nil
--- if none. (Every word typed, 3 letters or more, in its name)
function Pins.FakeItemVendor(query)
	local words = {}
	for w in (query or ""):lower():gmatch("%S+") do
		if #w < 3 then return end
		words[#words + 1] = w
	end
	if #words == 0 then return end
	for vid, list in pairs(ns.FakeWares) do
		for _, it in ipairs(list) do
			local l, all = it.name:lower(), true
			for _, w in ipairs(words) do
				if not l:find(w, 1, true) then all = false break end
			end
			if all then return vid, it end
		end
	end
end

-- 1 April: the island turns up on the map by itself, for everyone, all day (at one spot for the
-- day, kept). A search's clearing leaves it be (back at the day's spot, if a secret search moved it)
local aprilSpot
local function AprilFools()
	if ns.aprilTest then return true end
	local t = date("*t")
	return t.month == 4 and t.day == 1, t
end

--- the island for April Fools' Day, if it's today (the map's just opened); gone again after
function Pins.AprilFools()
	local today, t = AprilFools()
	if not today then
		if island and island.ambient then
			island.ambient, aprilSpot = nil, nil
			island.on = false
			island:Hide()
		end
		return
	end
	t = t or date("*t")
	local saved = ns.db.aprilIsland
	if not (saved and saved.year == t.year and saved.yday == t.yday and not ns.aprilTest) then
		local ui, x, y = Pins.IslandSpot()
		saved = { year = t.year, yday = t.yday, ui = ui, x = x, y = y }
		if not ns.aprilTest then ns.db.aprilIsland = saved end
	end
	aprilSpot = saved
	if not (island and island.on) then Pins.ShowIsland(saved.ui, saved.x, saved.y) end
	if island then island.ambient = true end
end

--- where the island is now (its continent's map, 0..1), or nil when it isn't out
function Pins.IslandWhere()
	if island and island.on and islandAt then return islandAt.ui, islandAt.x, islandAt.y end
end

function Pins.Clear()
	farmUp = false
	if flashTimer then flashTimer:Cancel() flashTimer = nil end
	HideArea()
	if island then
		if island.ambient and aprilSpot then
			-- (April Fools: it stays, at the day's spot)
			if not (islandAt and islandAt.ui == aprilSpot.ui and islandAt.x == aprilSpot.x and islandAt.y == aprilSpot.y) then
				Pins.ShowIsland(aprilSpot.ui, aprilSpot.x, aprilSpot.y)
			end
		else
			island.on = false
			island:Hide()
		end
	end
	if card then card:Hide() end
	local W = QuestieWaypoints()
	if W and W.RemoveOwner then
		for _, f in ipairs(active) do
			if f.anchor then pcall(W.RemoveOwner, f.anchor) end
		end
	end
	if ns.MapPaths then ns.MapPaths.Clear() end
	if HBDPins then
		HBDPins:RemoveAllWorldMapIcons(REF)
		HBDPins:RemoveAllMinimapIcons(REF)
	end
	for _, m in ipairs(farmMinis) do
		m.frame:SetAlpha(1)
		if m.frame.hollow then m.frame.hollow:Hide() end
		m.frame.dot:Show()
	end
	wipe(farmMinis)
	if farmTicker then farmTicker:Cancel() farmTicker = nil end
	for i = #active, 1, -1 do
		local f = active[i]
		StopFlash(f)
		StopBig(f)
		if f.beacon then
			f.wave:Stop()
			f.beacon:Hide()
		end
		f.qms = nil
		f.halo:Hide()
		f:Hide()
		if f.anchor then f.anchor:Hide() end
		tinsert(f.mini and pool.mini or pool.world, f)
		active[i] = nil
	end
end

--------------------------------------------------------------------------------
-- A new search's world map markers start big, hold, then shrink to their size.
-- (World map only: a minimap marker is placed by its offset from the minimap's centre,
-- which its scale would change.)
--------------------------------------------------------------------------------

local BIG = 1.5                   -- times their size at first
local BIG_HOLD = 3                -- seconds they stay big
local SHRINK = 0.25               -- seconds to shrink back
local bigSince

local grower = CreateFrame("Frame")
grower:Hide()
grower:SetScript("OnUpdate", function(self)
	local t = GetTime() - bigSince - BIG_HOLD
	if t < 0 then return end
	local s = t >= SHRINK and 1 or BIG - (BIG - 1) * (t / SHRINK)
	for _, f in ipairs(active) do
		if f.big then
			f:SetScale(s)
			if s == 1 then f.big = nil end
		end
	end
	if s == 1 then self:Hide() end
end)

function StartBig(f)
	if f.mini then return end
	f.big = true
	f:SetScale(BIG)
end

function StopBig(f)
	f.big = nil
	f:SetScale(1)
end

-- markers kept after the pulse: as set, and always where an item's found (an area to farm in,
-- a herb's plants: gone while you look over the map, they'd be no use)
local function Keep()
	if ns.db.keep then return true end
	for _, f in ipairs(active) do
		if f.qms and f.qms.kind == "DROPS" then return true end
	end
	return false
end

--- whether the map shows where an item's found (its areas, a herb's plants): those stay while
--- the map's open and go when it closes, whatever the settings for other searches
function Pins.HasDrops()
	for _, f in ipairs(active) do
		if f.qms and f.qms.kind == "DROPS" then return true end
	end
	return false
end

--- Pulse the markers (all of them, or only one NPC's), then settle or go.
--- false: quiet (a search shown again, e.g. for another zone): no pulse, when markers are kept.
function Pins.Flash(npcId)
	if npcId == false then
		if Keep() then
			if flashTimer then flashTimer:Cancel() flashTimer = nil end
			for _, f in ipairs(active) do StopFlash(f) StopBig(f) end
			return
		end
		npcId = nil
	end
	if flashTimer then flashTimer:Cancel() end
	for _, f in ipairs(active) do
		if not npcId or (f.qms and f.qms.id == npcId) then
			StartFlash(f)
			StartBig(f)
		else
			StopFlash(f)
			StopBig(f)
		end
	end
	bigSince = GetTime()
	grower:Show()
	flashTimer = C_Timer.NewTimer(ns.db.flash, function()
		flashTimer = nil
		if Keep() then
			for _, f in ipairs(active) do StopFlash(f) end
		else
			Pins.Clear()
		end
	end)
end

--- The nearest match on your continent: marks it with a steady green ring. Returns its
--- details (as its markers' tooltips have them) and how far it is, or nil.
-- the nearest by the way there: of the markers within reach of the nearest as the crow flies
-- (a few, the nearest first), the one the quickest route gets to soonest. Only with the map open
-- (the networks it plans on are let go once it's closed a while); the answer kept until you've
-- moved, or the markers have
local ROUTE_FEW = 5          -- markers planned to, at most
local ROUTE_CLOSE = 120      -- yards: the nearest this close is it, no planning
local ROUTE_REACH = 2.5      -- markers this many times as far as the nearest, or ...
local ROUTE_PLUS = 1500      -- ... this many yards farther, whichever's more, are planned to
local ROUTE_MOVE = 30        -- yards you move before it's worked out again
local quickKey, quickPick
local function Quickest(near, best, far)
	if not (best and far and far > ROUTE_CLOSE and #near > 1) then return end
	if not (ns.Route and ns.Route.Time and WorldMapFrame and WorldMapFrame:IsShown()) then return end
	-- (in a city: its streets aren't in the networks, so a route there goes by its gates)
	if ns.Route.InCity and ns.PlayerMap and ns.Route.InCity(ns.PlayerMap()) then return end
	table.sort(near, function(a, b) return a.yd < b.yd end)
	local reach = math.max(far * ROUTE_REACH, far + ROUTE_PLUS)
	local list = {}
	for _, n in ipairs(near) do
		if #list >= ROUTE_FEW or n.yd > reach then break end
		list[#list + 1] = n
	end
	if #list < 2 then return end
	-- (the same markers, you about where you were: as before)
	local px, py = HBD:GetPlayerWorldPosition()
	local function Spot(d) return ("%d:%.2f:%.2f"):format(d.ui or 0, d.x or 0, d.y or 0) end
	local key = { math.floor((px or 0) / ROUTE_MOVE), math.floor((py or 0) / ROUTE_MOVE) }
	for _, n in ipairs(list) do key[#key + 1] = Spot(n.f.qms) end
	key = table.concat(key, "|")
	if key ~= quickKey then
		quickKey, quickPick = key, nil
		local bestSecs
		for i, n in ipairs(list) do
			local secs = ns.Route.Time(n.f.qms)
			-- (one it can't plan to: none of them by route, the crow's nearest it is)
			if not secs then quickPick = nil break end
			if not bestSecs or secs < bestSecs then bestSecs, quickPick = secs, i end
		end
		quickPick = quickPick and Spot(list[quickPick].f.qms)   -- (where it is: the markers are made anew)
	end
	if not quickPick then return end
	for _, n in ipairs(list) do
		if Spot(n.f.qms) == quickPick then return n.f, n.yd end
	end
end

function Pins.Nearest()
	local best, far
	-- (one marked as the one: it, near or far. A graveyard search's: where you'd come back)
	for _, f in ipairs(active) do
		local yd = not f.mini and f.qms and f.qms.pick and Distance(f.qms)
		if yd then
			for _, g in ipairs(active) do g.halo:Hide() end
			f.halo:Show()
			return f.qms, yd
		end
	end
	-- (a herb's plants beside its vendors: the nearest plant, it's what's to be found)
	local drops = false
	for _, f in ipairs(active) do
		if not f.mini and f.qms and f.qms.kind == "DROPS" then drops = true break end
	end
	local near = {}
	for _, f in ipairs(active) do
		f.halo:Hide()
		if not f.mini and f.qms and (not drops or f.qms.kind == "DROPS") then
			local yd = Distance(f.qms)
			if yd then
				near[#near + 1] = { f = f, yd = yd }
				if not far or yd < far then best, far = f, yd end
			end
		end
	end
	-- (of the nearest few as the crow flies, the quickest to get to: a river, a cliff or a
	-- flight path can make a farther one quicker)
	local quick, qyd = Quickest(near, best, far)
	if quick then best, far = quick, qyd end
	if best then best.halo:Show() end
	return best and best.qms, far
end

--- Make one match's marker stand out (on: pulse and grow), or settle it again (off). For the
--- nearest button: hovering it points out which marker it means.
function Pins.Spotlight(d, on)
	if not d then return end
	for _, f in ipairs(active) do
		if f.qms == d and not f.mini then
			if on then
				StartFlash(f)
				f:SetScale(1.4)
			else
				if not flashTimer then StopFlash(f) end   -- (still in a search's first pulse: leave it)
				if not f.big then f:SetScale(1) end
			end
		end
	end
end

local MINIMAP_FAR = 3   -- a pinned search: its nearest few outside your zone, on the minimap's edge

-- the maps that count as where you are, for the minimap: the map you're on, and up to its zone
-- (in a cave or a building with a map of its own, the results are on the zone's map)
local function HereMaps()
	local set, id, guard = {}, ns.PlayerMap(), 0
	while id and guard < 5 do
		set[id] = true
		local info = C_Map.GetMapInfo(id)
		if not info or (info.mapType or 0) <= 3 then break end   -- (3: a zone; up to there)
		id, guard = info.parentMapID, guard + 1
	end
	return set
end

--- Place markers for search results. Returns the number of world map markers placed and
--- whether the cap cut it short. pinned: the pinned search, whose nearest few outside your
--- zone also go on the minimap, held on its edge to point the way
function Pins.Show(results, service, quiet, pinned)
	Pins.Clear()
	if not HBDPins then return 0, false end
	Holder()
	Pins.Raise()
	local cap = ns.db.maxPins
	local here = ns.db.minimap and HereMaps()
	local far = {}            -- (pinned: the places outside your zone, for the minimap's edge)
	local placed, mini, cut = 0, 0, false
	local W = QuestieWaypoints()
	local NpcDB = ns.Index.DB()
	local paths = 0

	for _, r in ipairs(results) do
		local e = r.entry
		local kind = KindFor(e, service, r)
		local byMap = {}          -- uiMapID -> this NPC's marker there (its paths hang from it)
		for _, p in ipairs(r.points) do
			if placed >= cap then cut = true break end
			local d = { id = e.id, name = e.name, sub = e.sub, ui = p.ui, x = p.x, y = p.y, obj = e.obj,
				kind = kind, sells = r.sells, quests = r.quests, questStart = r.questStart, teaches = r.teaches,
				questEnd = r.questEnd, label = r.label, lines = r.lines, icon = r.icon, pick = r.pick, quest = r.quest,
			questNames = r.questNames }

			local f = Acquire(false)
			f.qms = d
			ApplyLook(f, kind)
			if d.icon then IconLook(f, d.icon) end
			if f.anchor then f.anchor.data = NewData(e.id) end
			HBDPins:AddWorldMapIconMap(REF, f.anchor or f, p.ui, p.x / 100, p.y / 100, SHOW_CONTINENT)
			byMap[p.ui] = f
			placed = placed + 1

			-- (a farming loop's veins or plants: on the minimap too, each hidden while it's within
			-- reach of the game's own tracking (FarmMiniTick). A mob farm's mobs: the map alone)
			if r.farm then
				farmUp = true
				-- (wherever you are now: it's put on the minimap as you come near it)
				if r.gathered and ns.db.minimap and #farmMinis < FARM_MINI_MAX and HBD then
					local wx, wy, winst = HBD:GetWorldCoordinatesFromZone(p.x / 100, p.y / 100, p.ui)
					if wx then
						local m = Acquire(true)
						m.qms = d
						ApplyLook(m, kind)
						if d.icon then IconLook(m, d.icon) end
						-- (a ring, hollow, and not the vein's or herb's picture: the game draws its own
						-- dot under every marker, never over one, so it has to show through the middle)
						if not m.hollow then
							local h = m:CreateTexture(nil, "OVERLAY", nil, 3)
							h:SetTexture(RING)
							h:SetPoint("CENTER")
							h:SetSize(m.size * 1.1, m.size * 1.1)
							m.hollow = h
						end
						m.hollow:SetVertexColor(1, 0.82, 0.3)
						m.hollow:Show()
						m.dot:Hide()
						m:Hide()
						local l = (e.name or ""):lower()
						farmMinis[#farmMinis + 1] = { frame = m, wx = wx, wy = wy, inst = winst, ui = p.ui, x = p.x, y = p.y, on = false,
							name = (e.name or ""):lower(),
							kind = (l:find("vein$") or l:find("deposit$")) and "ore" or "herb" }
						if not farmTicker then farmTicker = C_Timer.NewTicker(0.5, FarmMiniTick) end
					end
				end
			elseif here and here[p.ui] and mini < MINIMAP_MAX then
				local m = Acquire(true)
				m.qms = d
				ApplyLook(m, kind)
				if d.icon then IconLook(m, d.icon) end
				HBDPins:AddMinimapIconMap(REF, m, p.ui, p.x / 100, p.y / 100, false, true)
				mini = mini + 1
			elseif here and pinned then
				far[#far + 1] = d
			end
		end

		-- its patrol path, in each zone it has a marker in
		-- (drawn by MapSeek, from QuestieDB's own points: its markers are placed by its own code.
		-- By Questie, on its pins, only when its copy of the map library is what places them)
		local own = ns.MapPaths and not ns.mapLibOther
		if not e.obj and (own or W) and NpcDB and NpcDB.waypoints and paths < MAX_PATHS then
			local ok, wps = pcall(NpcDB.waypoints, e.id)
			if ok and type(wps) == "table" then
				for areaId, patrols in pairs(wps) do
					local ui = ns.UiMapFor(areaId)
					local f = type(patrols) == "table" and byMap[ui]
					if f and own then
						-- (hostile: friendly to neither faction, nor to yours)
						local mine = ns.faction == "Horde" and "H" or ns.faction == "Alliance" and "A" or nil
						local okF, fr = pcall(NpcDB.Get, e.id, "friendlyToFaction")   -- ("A", "H", "AH", or none)
						local hostile = not (okF and type(fr) == "string" and mine and fr:find(mine, 1, true))
						for _, patrol in ipairs(patrols) do ns.MapPaths.Add(ui, patrol, hostile, e.id) end
						paths = paths + 1
					elseif f and f.anchor and W then
						pcall(W.Add, f.anchor, "m_" .. e.id, patrols, areaId, false)
						paths = paths + 1
					end
				end
			end
		end
		if cut then break end
	end

	-- a pinned search: its nearest few on your continent but outside your zone, on the minimap's
	-- edge (none in your zone, it would show nothing there at all)
	if #far > 0 then
		local near = {}
		for _, d in ipairs(far) do
			local yd = Distance(d)
			if yd then near[#near + 1] = { d = d, yd = yd } end
		end
		table.sort(near, function(a, b) return a.yd < b.yd end)
		for i = 1, math.min(MINIMAP_FAR, #near) do
			local d = near[i].d
			local m = Acquire(true)
			m.qms = d
			ApplyLook(m, d.kind)
			HBDPins:AddMinimapIconMap(REF, m, d.ui, d.x / 100, d.y / 100, false, true)
		end
	end

	-- (an item's areas: drawn)
	local areas = {}
	for _, r in ipairs(results) do
		if r.area then areas[#areas + 1] = r.area end
	end
	if #areas > 0 then Pins.ShowArea(areas) end

	if quiet then Pins.Flash(false) else Pins.Flash() end

	-- only a few: each gets a beacon, until the search is cleared
	if placed <= BEACON_MAX then
		for _, f in ipairs(active) do
			if f.beacon then
				f.beacon:Show()
				f.wave:Play()
				-- (and its small ring's pulse, if that's begun, let go)
				f.pulse:Stop()
				f.ring:Hide()
			end
		end
	end

	-- the maps the markers are on (to move the map to them)
	-- (a herb's plants beside its vendors: where the plants are)
	local maps, drops = {}, false
	for _, f in ipairs(active) do
		if not f.mini and f.qms and f.qms.kind == "DROPS" then drops = true break end
	end
	for _, f in ipairs(active) do
		if not f.mini and f.qms and (not drops or f.qms.kind == "DROPS") then maps[f.qms.ui] = true end
	end
	local nearest, yd = Pins.Nearest()
	return placed, cut, nearest, yd, maps
end
