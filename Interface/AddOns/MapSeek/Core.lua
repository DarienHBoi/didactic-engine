--------------------------------------------------------------------------------
-- MapSeek: type into a box on the world map, and every matching NPC from
-- Questie's database (vendors, trainers, innkeepers, any NPC by name) flashes on the map.
--
-- Data:  QuestieDB's public NpcDB (name, subName, npcFlags, spawns, friendlyToFaction).
-- Zones: Questie's ZoneDB (AreaID -> UiMapID).
-- Pins:  Questie's own copy of HereBeDragons-Pins, the same path Questie's townsfolk icons
--        take, so they land in the same place on Blizzard's map and on OpenMap's stitched one.
--------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L
ns.name = ADDON

--- the map library, HereBeDragons ("HBD") or its pins ("HBDPins"). Questie's own copy first: a
--- module of Questie's now (QuestieLoader), with WoW Forever's zones in it and the
--- minimap's view; it was a library by a name of its own before that. Then any other addon's
--- copy of the library proper. nil when there's none (probe: a function it must have)
function ns.MapLib(module, probe)
	-- (MapSeek's own, Map.lua: what's used. It hands on to Questie's copy itself, when that's
	-- asked for with "/seek maplib questie")
	if module == "HBD" and ns.Map then return ns.Map end
	if module == "HBDPins" and ns.MapPins then return ns.MapPins end
	local loader = _G.QuestieLoader
	if loader and loader.ImportModule then
		local ok, mod = pcall(loader.ImportModule, loader, module)
		-- (asked for a module it hasn't, the loader hands back an empty one)
		if ok and type(mod) == "table" and type(mod[probe]) == "function" then return mod end
	end
	if not LibStub then return end
	local name = module == "HBDPins" and "-Pins-2.0" or "-2.0"
	local lib = LibStub("HereBeDragonsQuestie" .. name, true) or LibStub("HereBeDragons" .. name, true)
	if lib and type(lib[probe]) == "function" then return lib end
end

local defaults = {
	flash = 6,             -- seconds the markers pulse
	linger = 30,           -- seconds a quick button's search stays after the map closes (0: none)
	keep = true,           -- markers stay (steady) after the flash, until cleared
	minimap = true,        -- markers in your current zone also go on the minimap
	farmWorth = true,      -- farming loops show what an hour might make at auction, when a price addon's there
	dots = false,          -- a farming loop's minimap markers hide where the game's own tracking dot shows (Pins.lua)
	maxPins = 400,         -- world map markers at most per search
	otherFaction = false,  -- include NPCs friendly only to the other faction
	closeClears = "all",   -- closing the map clears: "all" (search and markers) or "list" (search only)
	buttons = { "repair", "inn", "trainer" },   -- the quick buttons on the bar, in order (UI.lua)
	recent = true,         -- remember recent searches
	recentMax = 3,         -- ... and how many to show
	searchOpen = true,     -- the search box is open whenever the map opens (over the breadcrumbs)
	minimapIcon = { hide = false },   -- the minimap button (LibDBIcon keeps its place here too)
	ownClass = true,       -- a "trainer" search shows your class's trainers only
	ownProfs = true,       -- ... and, once both main professions are picked, only theirs
	zoneOnly = false,      -- search only the zone (or continent) the map shows
	favorites = {},        -- starred searches, at the top of the list
	favIcons = {},         -- a starred search on the bar: its icon (a look in Pins.lua)
	minimapButtons = {},   -- the favourites the minimap button offers (up to 6 searches), in order
	minimapSide = "left",  -- which way they open from the button: "left", "right", "down", "up"
	font = "",             -- the font MapSeek's texts use: "" the game's own, else a shared font's name
	miniRoute = true,      -- a route's line, and a farming loop's, on the minimap
	repairAlert = true,    -- offer to find a repair when your gear is wearing out
	focus = true,          -- move the map to the results (their zone, when they're all in one)
	history = {},          -- the recent searches, newest first
	barPos = "top",        -- where the search bar sits: "top", "bottom" or "custom" (barAt: where)
}

function ns.Print(msg)
	print("|cff33ccffMapSeek|r: " .. tostring(msg))
end

-- the uiMapID you're in (nil if the game won't say)
function ns.PlayerMap()
	local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
	if ok and type(id) == "number" then return id end
end

-- the maps whose matches come first: the one the world map shows, and the one you're in
function ns.PriorityMaps()
	local set = {}
	local shown = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
	if shown then set[shown] = true end
	local here = ns.PlayerMap()
	if here then set[here] = true end
	return set
end

function ns.ZoneName(uiMapID)
	local info = uiMapID and C_Map.GetMapInfo(uiMapID)
	return info and info.name or "?"
end

--------------------------------------------------------------------------------
-- The repair reminder: gear down to 20%, out of combat and alive: "Find a repair?" Once each
-- time it wears down (it asks again after you've repaired).
--------------------------------------------------------------------------------

local REPAIR_AT = 0.2
local warned, held

local function LowestDurability()
	local low
	for slot = 1, 18 do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 and (not low or cur / max < low) then low = cur / max end
	end
	return low
end

StaticPopupDialogs.MAPSEEK_REPAIR = {
	text = L["MapSeek: your gear is down to %s. Find the nearest repair?"],
	button1 = L["Find a repair"],
	button2 = L["Not now"],
	OnAccept = function() ns.UI.GoNearest("repair") end,
	timeout = 30,
	whileDead = false,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function CheckDurability()
	if not (ns.db and ns.db.repairAlert) then return end
	local low = LowestDurability()
	if not low then return end
	if low > REPAIR_AT + 0.05 then warned = false return end    -- (repaired: ask again next time)
	if low > REPAIR_AT or warned then return end
	if InCombatLockdown() or UnitIsDeadOrGhost("player") or (MerchantFrame and MerchantFrame:IsShown()) then
		held = true                                              -- (later: out of combat, alive)
		return
	end
	warned, held = true, false
	StaticPopup_Show("MAPSEEK_REPAIR", ("%d%%"):format(low * 100))
end

--- an item's icon, for what a vendor sells in its tooltip (any item: no need for it to be cached)
function ns.ItemIcon(item)
	-- (below zero: one of GM Island's, which aren't real; Pins.lua)
	if type(item) == "number" and item < 0 then
		local fake = ns.FakeItems and ns.FakeItems[item]
		return fake and fake.icon or 134400
	end
	local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item)
	if not icon and GetItemIcon then icon = GetItemIcon(item) end
	return icon or 134400   -- (the question mark)
end

--------------------------------------------------------------------------------
-- EllesmereUI's skin, when it's installed and its third-party skinning is on for MapSeek: EUI
-- hands over its skinning API (S) at login, and every frame of ours is painted in your EUI
-- theme. Without it, nothing here runs and the frames keep their own look.
--------------------------------------------------------------------------------

local skinWaiting = {}

local function SkinRun(fn, S)
	local ok, err = pcall(fn, S)
	if not ok then geterrorhandler()(err) end
end

--- fn(S) now if EUI's skin is here, else once it comes (never, without EUI)
function ns.OnSkin(fn)
	if ns.skin then SkinRun(fn, ns.skin) else skinWaiting[#skinWaiting + 1] = fn end
end

if EllesmereUI and EllesmereUI.RegisterSkin then
	EllesmereUI.RegisterSkin("MapSeek", function(S)
		ns.skin = S
		for _, fn in ipairs(skinWaiting) do SkinRun(fn, S) end
		wipe(skinWaiting)
	end)
end

--- a frame of ours with a backdrop: EUI's flat panel in its place (opts: S.Panel's)
function ns.SkinPanel(f, opts)
	ns.OnSkin(function(S)
		if f.SetBackdrop then f:SetBackdrop(nil) end
		if f.plainBg then f.plainBg:Hide() end
		S.Panel(f, opts)
	end)
end

--- a small X of ours (a button, and its own X texture): EUI's close glyph in its place
function ns.SkinClose(b, tex)
	ns.OnSkin(function(S)
		if not S.CloseButton then return end
		if tex then tex:Hide() end
		S.CloseButton(b)
	end)
end

--- font strings in EUI's font (same size and colour)
function ns.SkinText(...)
	local list = { ... }
	ns.OnSkin(function(S) for _, t in ipairs(list) do S.Font(t) end end)
end

--------------------------------------------------------------------------------
-- A small menu of the game's own, at the cursor: the newer menus (MenuUtil) or the older
-- drop-downs. items: { title = text } | { divider = true } | { text, func, checked = fn,
-- radio = true, look = a look from Pins.lua }. false when this client has neither
--------------------------------------------------------------------------------

--- a look (Pins.lua) as a texture escape, to put before a menu line's text
function ns.LookEscape(look)
	if not look then return "" end
	if look.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(look.atlas) then
		return "|A:" .. look.atlas .. ":16:16|a "
	end
	local path, c = look[1], look.coords
	if c then
		return ("|T%s:16:16:0:0:256:256:%d:%d:%d:%d|t "):format(path, c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
	elseif path:find("^Interface\\Icons\\") then
		return "|T" .. path .. ":16:16:0:0:64:64:5:59:5:59|t "
	end
	return "|T" .. path .. ":16:16|t "
end

local dropdown
function ns.OpenMenu(owner, items)
	local function Label(it) return (it.look and ns.LookEscape(it.look) or "") .. it.text end
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			if #items > 22 and root.SetScrollMode then root:SetScrollMode(22 * 20) end
			for _, it in ipairs(items) do
				if it.title then
					root:CreateTitle(it.title)
				elseif it.divider then
					root:CreateDivider()
				elseif it.checked then
					local function Set()
						it.func()
						return MenuResponse and MenuResponse.Close
					end
					if it.radio then root:CreateRadio(Label(it), it.checked, Set)
					else root:CreateCheckbox(Label(it), it.checked, Set) end
				else
					root:CreateButton(Label(it), it.func)
				end
			end
		end)
		return true
	end
	if not (UIDropDownMenu_Initialize and ToggleDropDownMenu) then return false end
	dropdown = dropdown or CreateFrame("Frame", "MapSeekDropDown", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(dropdown, function()
		for _, it in ipairs(items) do
			if it.divider then
				if UIDropDownMenu_AddSeparator then UIDropDownMenu_AddSeparator(1) end
			else
				local info = UIDropDownMenu_CreateInfo()
				if it.title then
					info.text, info.isTitle, info.notCheckable = it.title, true, true
				else
					info.text = Label(it)
					info.func = function() it.func() CloseDropDownMenus() end
					if it.checked then
						info.checked = it.checked()
						info.isNotRadio = not it.radio
					else
						info.notCheckable = true
					end
				end
				UIDropDownMenu_AddButton(info, 1)
			end
		end
	end, "MENU")
	ToggleDropDownMenu(1, nil, dropdown, "cursor", 0, 0)
	return true
end

--------------------------------------------------------------------------------
-- Fonts: the game's own, or one addons share through LibSharedMedia ("Numen", from FojjiCore,
-- say). Every text of MapSeek's uses a font object of its own, copied from the game's it would
-- have used (GameFontNormal...), so a change of font changes them all at once, sizes kept.
--------------------------------------------------------------------------------

local fonts = {}      -- [base name] = our Font object, copied from the game's
local texts = setmetatable({}, { __mode = "k" })   -- [font string] = base name
local outlined = {}   -- texts with a size and outline of their own: { text, size, flags }
-- (the game's own faces, for a pick without LibSharedMedia)
local BUILT_IN = {
	["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF", ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
	["Morpheus"] = "Fonts\\MORPHEUS.TTF", ["Skurri"] = "Fonts\\SKURRI.TTF",
}

--- the file of the font picked, or nil for the game's own
function ns.FontPath()
	local name = ns.db and ns.db.font
	if not name or name == "" then return nil end
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	local path = LSM and LSM:Fetch("font", name, true)
	return path or BUILT_IN[name]
end

--- the fonts there are to pick from: { name, ... } sorted, the shared ones (or the game's own faces)
function ns.FontList()
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	local list = {}
	if LSM then
		for _, name in ipairs(LSM:List("font")) do list[#list + 1] = name end
	else
		for name in pairs(BUILT_IN) do list[#list + 1] = name end
	end
	table.sort(list)
	return list
end

local function Style(f, base)
	if f.CopyFontObject then f:CopyFontObject(base) else f:SetFontObject(base) end
	local path = ns.FontPath()
	if path then
		local _, size, flags = f:GetFont()
		f:SetFont(path, size or 12, flags or "")
	end
end

--- our font object for a game font ("GameFontNormal"): the same, in the font picked
function ns.Font(base)
	local f = fonts[base]
	if not f then
		f = CreateFont("MapSeekFont" .. base)
		fonts[base] = f
		Style(f, base)
	end
	return f
end

--- a font string of ours, as the game font would have it, in the font picked
function ns.Text(parent, base, layer)
	local t = parent:CreateFontString(nil, layer or "OVERLAY", base)
	t:SetFontObject(ns.Font(base))
	texts[t] = base
	return t
end

--- a frame with text of its own (an edit box) in the font picked, as its font would have it
function ns.UseFont(frame, base)
	if not base then
		local fo = frame.GetFontObject and frame:GetFontObject()
		base = fo and fo.GetName and fo:GetName() or "ChatFontNormal"
	end
	frame:SetFontObject(ns.Font(base))
	texts[frame] = base
end

--- a text with a size and outline of its own (a label on the map), in the font picked
function ns.Outline(t, size, flags)
	flags = flags or "OUTLINE"
	local path = ns.FontPath() or t:GetFont() or STANDARD_TEXT_FONT
	t:SetFont(path, size, flags)
	outlined[#outlined + 1] = { t, size, flags }
end

--- the font's changed: every text of ours again
function ns.ApplyFonts()
	for base, f in pairs(fonts) do Style(f, base) end
	for t, base in pairs(texts) do t:SetFontObject(ns.Font(base)) end
	for _, o in ipairs(outlined) do
		local path = ns.FontPath() or select(1, ns.Font("GameFontNormal"):GetFont()) or STANDARD_TEXT_FONT
		o[1]:SetFont(path, o[2], o[3])
	end
end

--------------------------------------------------------------------------------
-- The minimap button: click to search (Questie's copies of LibDataBroker and LibDBIcon)
--------------------------------------------------------------------------------

local ICON = "Interface\\AddOns\\MapSeek\\Media\\icon"

local function MinimapButton()
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
	if not (LDB and DBI) or DBI:IsRegistered(ADDON) then return end
	local obj = LDB:NewDataObject(ADDON, {
		type = "launcher",
		label = "MapSeek",
		icon = ICON,
		OnClick = function(_, button)
			if button == "RightButton" then
				ns.Settings.Toggle()
			else
				ns.UI.MinimapClick(IsShiftKeyDown())
			end
		end,
		OnTooltipShow = function(tt)
			tt:AddLine("|cffeceff2Map|r|cffffc828Seek|r")
			if #ns.UI.MiniSpecs() > 0 then
				tt:AddLine(L["Click for your quick searches"], 1, 1, 1)
				tt:AddLine(L["Shift-click to search the map"], 0.7, 0.7, 0.7)
			else
				tt:AddLine(L["Click to search the map"], 1, 1, 1)
			end
			tt:AddLine(L["Right-click for the settings"], 0.7, 0.7, 0.7)
			tt:AddLine(L["Drag to move it"], 0.7, 0.7, 0.7)
		end,
	})
	if obj then DBI:Register(ADDON, obj, ns.db.minimapIcon) end
end

--- show or hide the minimap button (the settings)
function ns.SetMinimapButton(show)
	ns.db.minimapIcon.hide = not show
	local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
	if not DBI then return end
	if show then
		if not DBI:IsRegistered(ADDON) then MinimapButton() end
		DBI:Show(ADDON)
	else
		DBI:Hide(ADDON)
	end
end

-- "Find on Map" in the right-click menu of someone in your group (their party or raid frame, or
-- them as your target): the map opens on where they are
local SEEK_MENUS = { "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_RAID", "MENU_UNIT_TARGET",
	"MENU_UNIT_FOCUS", "MENU_UNIT_FRIEND" }
local SEEK_WHICH = { PARTY = true, RAID_PLAYER = true, RAID = true, TARGET = true, FOCUS = true, FRIEND = true }

local function GroupName(unit, name)
	if unit and UnitExists(unit) then
		if UnitIsUnit(unit, "player") or not (UnitInParty(unit) or UnitInRaid(unit)) then return end
		return (UnitName(unit))
	end
	-- (a raid list row has only the name: one of the raid's, then)
	name = name and name:match("^[^%-]+")
	if not name then return end
	for _, u in ipairs(ns.Search.GroupUnits()) do
		if UnitName(u) == name then return name end
	end
end

local function SeekMenu()
	local function Seek(name) ns.UI.SearchFromSlash(name) end
	if Menu and Menu.ModifyMenu then
		for _, tag in ipairs(SEEK_MENUS) do
			Menu.ModifyMenu(tag, function(_, root, context)
				local name = context and GroupName(context.unit, context.name)
				if not name then return end
				root:CreateDivider()
				root:CreateButton(L["Find on Map"], function() Seek(name) end)
			end)
		end
	elseif UnitPopup_ShowMenu and UIDropDownMenu_AddButton then
		-- (the older menus: a line added once the menu's shown, as it's being shown)
		hooksecurefunc("UnitPopup_ShowMenu", function(_, which, unit, name)
			if UIDROPDOWNMENU_MENU_LEVEL ~= 1 or not SEEK_WHICH[which] then return end
			local who = GroupName(unit, name)
			if not who then return end
			local info = UIDropDownMenu_CreateInfo()
			info.text = L["Find on Map"]
			info.notCheckable = true
			info.func = function() Seek(who) end
			UIDropDownMenu_AddButton(info, 1)
		end)
	end
end

--------------------------------------------------------------------------------
-- Questie, newly installed along with MapSeek: set up once, the way that sits best with it (the
-- game's own quest objectives on the map, not Questie's; its tracker and its chat lines off).
-- Only a Questie nobody's used yet: no character but this one known to it, no quest it's seen
-- handed in, its "which objectives?" question never answered. One that's been used is left
-- exactly as it is. Asked once, MapSeek's own first load, never again.
--------------------------------------------------------------------------------

--- memory just let go in bulk (a list of farms worked out): the game's collector hurried through
--- it, a little each frame for a few seconds (all at once would stop the game a moment: it
--- sweeps every addon's memory, not MapSeek's alone)
local sweeping
function ns.Sweep()
	if sweeping or not (C_Timer and C_Timer.NewTicker and collectgarbage) then return end
	local left, rounds = 400, 0   -- (frames: some seconds)
	sweeping = C_Timer.NewTicker(0.01, function(t)
		left = left - 1
		-- (true: a round of collecting done. Two: the one it was part-way through when asked,
		-- which may have looked at this memory before it was let go, and a whole one after)
		if collectgarbage("step", 300) then rounds = rounds + 1 end
		if rounds >= 2 or left <= 0 then
			t:Cancel()
			sweeping = nil
		end
	end)
end

local function QuestieIsNew()
	local sv = _G.QuestieConfig
	local Q = _G.Questie
	if type(sv) ~= "table" or type(Q) ~= "table" or type(Q.db) ~= "table" then return false end
	if type(sv.global) == "table" and sv.global.tutorialObjectiveTypeChosen then return false end
	local chars = 0
	for _ in pairs(type(sv.profileKeys) == "table" and sv.profileKeys or {}) do chars = chars + 1 end
	if chars > 1 then return false end
	for _, c in pairs(type(sv.char) == "table" and sv.char or {}) do
		if type(c) == "table" then
			if type(c.complete) == "table" and next(c.complete) then return false end
			if type(c.journey) == "table" and next(c.journey) then return false end
		end
	end
	return true
end

--- Questie set the way that sits best with MapSeek (quiet: true), or back as Questie itself
--- comes (false): its objectives, its tracker, its chat lines. true when it was. It shows after
--- a reload
function ns.QuestieQuiet(quiet)
	local Q = _G.Questie
	local db = type(Q) == "table" and Q.db
	if type(db) ~= "table" then return false end
	local ok = pcall(function()
		local prof = db.profile
		prof.iconTheme = quiet and "blizzard" or "questie"
		prof.enableObjectives = not quiet
		prof.trackerEnabled = not quiet
		prof.questieShutUp = quiet and true or false
		db.global.tutorialObjectiveTypeChosen = true
	end)
	-- (the game's own objectives on the map, or not: as Questie's own choice of them sets it)
	if ok and GetCVar and SetCVar then
		local want = quiet and "1" or "0"
		local okC, poi = pcall(GetCVar, "questPOI")
		if okC and poi ~= nil and poi ~= want then pcall(SetCVar, "questPOI", want) end
	end
	return ok
end

--- whether Questie is set that way now
function ns.QuestieIsQuiet()
	local Q = _G.Questie
	local db = type(Q) == "table" and Q.db
	if type(db) ~= "table" then return false end
	local ok, quiet = pcall(function()
		local prof = db.profile
		return prof.enableObjectives == false and prof.trackerEnabled == false and prof.questieShutUp == true
	end)
	return ok and quiet or false
end

local function QuestieSetUp()
	if not QuestieIsNew() then return end
	return ns.QuestieQuiet(true)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_UNGHOST")
ev:RegisterEvent("PLAYER_ALIVE")
ev:RegisterEvent("MERCHANT_CLOSED")
ev:SetScript("OnEvent", function(self, event, arg)
	if event == "ADDON_LOADED" and arg == ADDON then
		local fresh = MapSeekDB == nil
		MapSeekDB = MapSeekDB or {}
		for k, v in pairs(defaults) do
			if MapSeekDB[k] == nil then
				MapSeekDB[k] = type(v) == "table" and CopyTable(v) or v
			end
		end
		MapSeekDB.stock, MapSeekDB.prices = nil, nil   -- (price notes from a test build, no longer kept)
		ns.db = MapSeekDB
		-- (Questie's copy of the map library asked for, and still there: used, not MapSeek's own)
		ns.mapLibOther = MapSeekDB.mapLib == "questie" and ns.MapLibHasOther and ns.MapLibHasOther() or false
		if fresh then pcall(QuestieSetUp) end
		ns.UI.MergeFavorites(fresh)
		ns.UI.SeedMini()
	elseif event == "UPDATE_INVENTORY_DURABILITY" then
		CheckDurability()
	elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE"
		or event == "MERCHANT_CLOSED" then
		if held then CheckDurability() end
	elseif event == "ADDON_LOADED" and arg == "Blizzard_WorldMap" and ns.db then
		ns.UI.Create()   -- (in case the map wasn't loaded yet at login)
	elseif event == "PLAYER_LOGIN" then
		ns.faction = UnitFactionGroup("player")
		ns.UI.Create()
		pcall(MinimapButton)
		pcall(SeekMenu)
		-- (the data is QuestieDB's, there once it's loaded. With Questie too: once Questie's ready,
		-- its own corrections to the data laid over it. Without: now)
		local LQ = _G.LibQuestieDB
		if Questie and Questie.API and Questie.API.RegisterOnReady then
			Questie.API.RegisterOnReady(function()
				ns.questieReady = true
				ns.Index.Start()
			end)
		elseif LQ and (LQ.Npc or _G.NpcDB) then
			-- (written against QuestieDB's contract 4; it says how far back and on it reads)
			local ok, why = true, nil
			if LQ.RequireContract then ok, why = LQ.RequireContract(4) end
			if not ok and why then ns.Print(why) end
			ns.questieReady = true
			ns.Index.Start()
		else
			ns.Print(L["QuestieDB isn't loaded, so there's nothing to search."])
		end
	end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local function OnOff(v, current)
	if v == "on" then return true elseif v == "off" then return false end
	return not current
end

local HELP = {
	L["/seek <text>  - open the map and search (e.g. /seek repair, /seek fishing trainer)"],
	L["/seek clear  - remove the markers"],
	L["/seek flash <seconds>  - how long markers pulse (now %d)"],
	L["/seek keep on|off  - keep markers after the flash (now %s)"],
	L["/seek minimap on|off  - markers on the minimap too (now %s)"],
	L["/seek faction on|off  - include the other faction's NPCs (now %s)"],
	L["/seek close all|list  - closing the map clears everything, or only the search and list (now %s)"],
	L["/seek config  - open the settings (also the gear at the end of the search bar)"],
	L["/seek button on|off  - the minimap button (now %s)"],
}

SLASH_MAPSEEK1 = "/seek"
SLASH_MAPSEEK2 = "/mapseek"
SlashCmdList.MAPSEEK = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	local db = ns.db
	if cmd == "" or cmd == "help" then
		local yn = function(b) return b and L["on"] or L["off"] end
		ns.Print(L["commands:"])
		print(HELP[1]); print(HELP[2])
		print(HELP[3]:format(db.flash))
		print(HELP[4]:format(yn(db.keep)))
		print(HELP[5]:format(yn(db.minimap)))
		print(HELP[6]:format(yn(db.otherFaction)))
		print(HELP[7]:format(db.closeClears))
		print(HELP[8])
		print(HELP[9]:format(yn(not db.minimapIcon.hide)))
	elseif cmd == "config" or cmd == "settings" or cmd == "options" then
		ns.Settings.Toggle()
	elseif cmd == "paths" then
		if ns.MapPaths and ns.MapPaths.Debug then ns.MapPaths.Debug() end
	elseif cmd == "time" then
		-- (how long a search takes, the first time and again: for telling a slow search from a
		-- slow first look at the data)
		if rest == "" or not debugprofilestop then
			ns.Print("/seek time <search>")
		else
			local t0 = debugprofilestop()
			local r1 = ns.Search.Run(rest, true)
			local t1 = debugprofilestop()
			local r2 = ns.Search.Run(rest, true)
			local t2 = debugprofilestop()
			ns.Print(("\"%s\": first %.0f ms (%d found), again %.0f ms. Questie %s; QuestieDB reads as \"%s\"; markers by %s"):format(
				rest, t1 - t0, r1 and #r1 or 0, t2 - t1, _G.Questie and "loaded" or "not loaded",
				tostring(_G.LibQuestieDB and LibQuestieDB.readMode), ns.mapLibOther and "Questie's library" or "MapSeek"))
		end
	elseif cmd == "maplib" then
		-- (which places the markers: MapSeek's own code, or Questie's copy of the library. For
		-- telling which is at fault when one sits wrong; it takes a reload)
		if rest == "questie" or rest == "own" then
			if rest == "questie" and not (ns.MapLibHasOther and ns.MapLibHasOther()) then
				ns.Print(L["Questie's copy of the map library isn't there to use."])
			else
				db.mapLib = rest
				if ReloadUI then ReloadUI() end
			end
		else
			ns.Print((ns.mapLibOther and L["Markers are placed by Questie's copy of the map library."]
				or L["Markers are placed by MapSeek's own code."]) .. " /seek maplib own | questie")
		end
	elseif cmd == "mini" then
		if ns.Pins and ns.Pins.MiniDebug then ns.Pins.MiniDebug() end
	elseif cmd == "dots" then
		db.dots = OnOff(rest, db.dots)
		ns.Print(db.dots and L["farming markers on the minimap hide where the game's own tracking dot shows"]
			or L["farming markers on the minimap hide when you're near, while Find Minerals or Find Herbs is on"])
	elseif cmd == "questie" then
		-- ("quiet": Questie's tracker, objective icons and chat lines off; "default": back on)
		if rest == "quiet" or rest == "default" then
			if ns.QuestieQuiet(rest == "quiet") then
				if ReloadUI then ReloadUI() end
			else
				ns.Print(L["Questie isn't ready yet. Try again in a moment."])
			end
		else
			ns.Print(L["use /seek questie quiet  or  /seek questie default  (your UI reloads)"])
		end
	elseif cmd == "prices" or cmd == "price" then
		db.farmWorth = OnOff(rest, db.farmWorth ~= false)
		ns.Print(db.farmWorth and L["farming loops show what an hour might make at auction"]
			or L["farming loops don't show auction prices"])
	elseif cmd == "close" then
		if rest == "all" or rest == "list" then
			db.closeClears = rest
			ns.Print(rest == "all" and L["closing the map clears the search and the markers"]
				or L["closing the map clears the search; markers stay until you clear them"])
		else
			ns.Print(L["use /seek close all  or  /seek close list"])
		end
	elseif cmd == "april" then
		-- (not in the help: April Fools' Day, for this session, to try it out)
		ns.aprilTest = not ns.aprilTest
		if not ns.aprilTest then
			ns.Print("it's not 1 April")
			if WorldMapFrame and WorldMapFrame:IsShown() then ns.Pins.AprilFools() end
			return
		end
		-- (the map open for it, so it's there to see, and the map taken to it)
		if WorldMapFrame and not WorldMapFrame:IsShown() then
			if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
		end
		C_Timer.After(0.2, function()
			ns.Pins.AprilFools()
			local ui, x, y = ns.Pins.IslandWhere()
			if not ui then
				ns.Print("it's 1 April, but the island couldn't be put on the map")
				return
			end
			ns.Print(("it's 1 April (until you /reload, or /seek april again): the island's off %s at %.1f, %.1f")
				:format(ns.ZoneName(ui) or "?", x * 100, y * 100))
			ns.UI.GoToMap(ui, x, y, 4)
		end)
	elseif cmd == "debug" then
		ns.Pins.Debug()
	elseif cmd == "clear" then
		ns.UI.Clear()
	elseif cmd == "list" or cmd == "lists" then
		-- (the farm lists' window; "start", "stop": the list shown, farmed or not)
		if not ns.FarmList then return end
		if rest == "start" then ns.FarmList.Start()
		elseif rest == "stop" then ns.FarmList.Stop()
		else ns.FarmList.Toggle() end
	elseif cmd == "stop" then
		-- (the route followed, or the farming loop, stopped)
		if ns.Route and ns.Route.Active() then ns.Route.Stop() ns.Print(L["stopped"]) end
	elseif cmd == "flash" then
		local n = tonumber(rest)
		if n and n >= 1 and n <= 60 then db.flash = n ns.Print(L["markers pulse for %d seconds"]:format(n))
		else ns.Print(L["give a number of seconds from 1 to 60"]) end
	elseif cmd == "keep" then
		db.keep = OnOff(rest, db.keep)
		ns.Print(db.keep and L["markers stay after the flash"] or L["markers go away after the flash"])
	elseif cmd == "minimap" then
		db.minimap = OnOff(rest, db.minimap)
		ns.Print(db.minimap and L["minimap markers on"] or L["minimap markers off"])
	elseif cmd == "button" then
		ns.SetMinimapButton(OnOff(rest, not db.minimapIcon.hide))
		ns.Print(db.minimapIcon.hide and L["minimap button hidden"] or L["minimap button shown"])
	elseif cmd == "faction" then
		db.otherFaction = OnOff(rest, db.otherFaction)
		ns.Print(db.otherFaction and L["other faction's NPCs included"] or L["other faction's NPCs left out"])
	else
		ns.UI.SearchFromSlash(msg)
	end
end
