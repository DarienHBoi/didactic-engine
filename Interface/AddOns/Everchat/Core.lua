local addonName, ns = ...

ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version")

local PREFIX = "|cffffd100Everchat|r"

-- Options.lua reads the defaults too.
local DEFAULTS = {
	timestamps = true,
	guildBadge = true,
	-- "[General]" instead of "[1. General - Zephras Isle]" (Channels.lua).
	shortChannels = true,
	-- Quests, items and spells other players link, named in this client's
	-- language (Names.lua).
	localNames = true,
	-- Everchat's buttons on the side rail (Buttons.lua): copy, options and the
	-- audio alerts' bell (railMute, below) by default.
	railCopy = true,
	railClear = false,
	railOptions = true,
	railRoll = false,
	-- The chat's look: "gold", "silver" or "bronze", and the minimal style
	-- (no frame on the open tab) over it (Theme.lua).
	theme = "gold",
	themeMinimal = false,
	-- The chat while not in use (Skin.lua): "faded", as the game's chat does,
	-- "hidden", only new messages showing for a while, or "always" visible.
	chatRest = "faded",
	lockChat = false,
	-- ...and how long new messages show while it's hidden, in seconds.
	hideAtRestSeconds = 10,
	-- The chat's font: a key of Fonts.FONTS, or "game" for the game's own (Fonts.lua).
	chatFont = "roboto",
	-- "compact", "normal" or "wide" (Timestamps.lua).
	lineSpacing = "normal",
	-- "none" (the chat's shadow), "thin" or "thick" (Fonts.lua).
	fontOutline = "none",
	-- Logins, logouts and channel notices in grey (Channels.lua).
	muteNotices = true,
	-- Mentions of the account's other characters too (Alerts.lua).
	mentionAlts = true,
	-- Item icons before item links in Trade (Channels.lua).
	itemIcons = true,
	-- Repeated ads in numbered channels hidden for 5 minutes (Channels.lua).
	hideRepeats = true,
	-- Public lines mostly in these alphabets hidden (Filters.lua).
	hideHan = false,
	hideHangul = false,
	hideCyrillic = false,
	hideLatin = false,
	-- The player's name in gold when others write it; the tab lights up (Alerts.lua).
	mentions = true,
	-- ...and the whisper sound plays (Alerts.lua).
	mentionSound = true,
	-- No Everchat sounds at all until turned back on: the rail's bell (Alerts.lua).
	soundsMuted = false,
	railMute = true,
	-- The side bar's eye, going through the chat's states at rest (chatRest).
	railHide = true,
	-- No Everchat sounds in combat or inside instances (Alerts.lua).
	quietInCombat = false,
	-- A mark before friends' and guild members' names in public channels (Channels.lua).
	socialMarks = true,
	-- Medallions with the character's race portrait and class icon before
	-- names in every conversation channel (Channels.lua).
	raceMarks = false,
	classMarks = false,
	-- How players' surnames show in the chat: "full", "initial" or "hidden" (Channels.lua).
	surnames = "full",
	-- "inv" in whispers and guild lines invites their writer with a click (Links.lua).
	inviteLinks = true,
	-- The rail's search button (Search.lua).
	railSearch = true,
	-- Chat kept across reloads and logins (History.lua).
	keepHistory = true,
}

function ns.Print(...)
	print(PREFIX, ...)
end

-- The character's full name, "Name Surname": Forever's UnitName gives the
-- first name and the surname as two values, which Blizzard's own NameUtil
-- joins with this separator. The unmodified name, which no display option
-- changes.
local SURNAME_SEPARATOR = Constants.CharacterNameSeparatorConsts
	and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "

function ns.PlayerName()
	local name, surname = (UnitNameUnmodified or UnitName)("player")
	if surname and surname ~= "" then
		return name .. SURNAME_SEPARATOR .. surname
	end
	return name
end

-- The key each character's data is kept under: "Name Surname-Realm".
function ns.CharacterKey()
	return ns.PlayerName() .. "-" .. GetRealmName()
end

-- Data kept per character, by key.
local CHARACTER_STORES = {
	"alerts", "tabSounds", "tabSoundChoices", "tabOrder", "keptConflicts",
	"chatLayouts", "history", "fontSized", "fontRaised", "tabSetups",
}

-- Keys made from the first name alone ("Name-Realm", before Everchat read the
-- surname) move to the full key when that character logs in.
local function MoveCharacterData()
	local old = UnitName("player") .. "-" .. GetRealmName()
	local key = ns.CharacterKey()
	if old == key then
		return
	end
	for _, name in ipairs(CHARACTER_STORES) do
		local store = ns.db[name]
		if type(store) == "table" and store[old] ~= nil and store[key] == nil then
			store[key], store[old] = store[old], nil
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, loadedName)
	if event == "ADDON_LOADED" and loadedName == addonName then
		EverchatDB = EverchatDB or {}
		-- The font switch became a choice of fonts (2026-10-13).
		if EverchatDB.everchatFont ~= nil then
			EverchatDB.chatFont = EverchatDB.chatFont or (EverchatDB.everchatFont and "roboto" or "game")
			EverchatDB.everchatFont = nil
		end
		-- "Hide surnames" became a choice of three (2026-10-12).
		-- A test build had a grey minimal theme; silver's minimal style replaced it.
		if EverchatDB.theme == "minimal" then
			EverchatDB.theme, EverchatDB.themeMinimal = "silver", true
		end
		-- One switch for every group label's icon became one per kind of label
		-- (Options > Channels): turned off, it turns them all off.
		if EverchatDB.groupIcons == false then
			EverchatDB.groupIconsOff = EverchatDB.groupIconsOff or {}
			for _, kind in ipairs(ns.Channels.LABEL_KINDS) do
				if kind ~= "GUILD" and ns.Channels.HasIcon(kind) then
					EverchatDB.groupIconsOff[kind] = true
				end
			end
		end
		EverchatDB.groupIcons = nil
		-- A switch for hiding the chat at rest became a choice of three.
		if EverchatDB.hideAtRest ~= nil then
			EverchatDB.chatRest = EverchatDB.chatRest or (EverchatDB.hideAtRest and "hidden" or "faded")
			EverchatDB.hideAtRest = nil
		end
		if EverchatDB.firstNames ~= nil then
			EverchatDB.surnames = EverchatDB.surnames or (EverchatDB.firstNames and "hidden" or "full")
			EverchatDB.firstNames = nil
		end
		for key, value in pairs(DEFAULTS) do
			if EverchatDB[key] == nil then
				EverchatDB[key] = value
			end
		end
		-- The padlock's state, before the move button replaced it (v0.29.0).
		EverchatDB.locked = nil
		-- Kept by a development diagnostic in pre-release builds.
		EverchatDB.blockedLog = nil
		-- A pre-release option: plain arrows can't browse typed lines in Forever.
		EverchatDB.arrowHistory = nil
		ns.db = EverchatDB
		ns.defaults = DEFAULTS
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGOUT" then
		-- A reload or logout while the lines show plain keeps the real choices.
		ns.RestorePlain()
	elseif event == "PLAYER_LOGIN" then
		MoveCharacterData()
		-- The theme before anything is painted.
		ns.Theme.Set(ns.db.theme, ns.db.themeMinimal)
		-- Sizes first: the skins read them.
		ns.Fonts.Init()
		ns.Players.Init()
		ns.Skin.Init()
		ns.Timestamps.Init()
		-- Before History, whose saved lines it composes as they come back.
		ns.Names.Init()
		ns.Lines.Init()
		ns.Channels.Init()
		ns.Filters.Init()
		ns.Alerts.Init()
		ns.Scroll.Init()
		-- Last: the lines it adds back go through the others' hooks.
		ns.History.Init()
		ns.Conflicts.Init()
		ns.Links.Init()
		ns.Search.Init()
		ns.TabCopy.Init()
		ns.Options.Init()
		if ns.db.diag then
			ns.Print(ns.L.diagOn)
		end
		-- Only when the version changes: no line in the chat on every login.
		if ns.db.lastVersion ~= ns.version then
			ns.Print((ns.db.lastVersion and ns.L.updated or ns.L.installed):format(ns.version))
			ns.db.lastVersion = ns.version
		end
	end
end)

-- Slash command toggles: aliases in English and Spanish.
local function AfterTimestamps()
	ns.Timestamps.Refresh()
	if ns.db.timestamps and ns.Timestamps.GameShowsTimes() then
		ns.Print(ns.L.timestampsGameOn)
	end
end

local function AfterHistory()
	if not ns.db.keepHistory then
		ns.History.Clear()
		ns.Print(ns.L.historyCleared)
	end
end

local TOGGLES = {
	time = { key = "timestamps", label = "Timestamps", after = AfterTimestamps },
	hora = { key = "timestamps", label = "Timestamps", after = AfterTimestamps },
	emblem = { key = "guildBadge", label = "Guild emblem", after = function() ns.Lines.Refresh() end },
	channels = { key = "shortChannels", label = "Short channel names", after = function() ns.Lines.Refresh() end },
	canales = { key = "shortChannels", label = "Short channel names", after = function() ns.Lines.Refresh() end },
	emblema = { key = "guildBadge", label = "Guild emblem", after = function() ns.Lines.Refresh() end },
	history = { key = "keepHistory", label = "Chat history", after = AfterHistory },
	historial = { key = "keepHistory", label = "Chat history", after = AfterHistory },
}

local CLEAR_HISTORY = {
	["history clear"] = true,
	["historial borrar"] = true,
}

-- Everchat's share of each frame, from the game's own addon profiler
-- (C_AddOnProfiler, times in milliseconds; 2026-10-14): for a long session
-- in a busy capital before launch, and whenever the chat feels heavy.
local function ReportCPU()
	local profiler = C_AddOnProfiler
	local metric = Enum and Enum.AddOnProfilerMetric
	if not (profiler and metric and profiler.IsEnabled and profiler.IsEnabled()) then
		ns.Print(ns.L.cpuOff)
		return
	end
	local function Own(which)
		return profiler.GetAddOnMetric(addonName, which) or 0
	end
	ns.Print(ns.L.cpuEverchat:format(Own(metric.RecentAverageTime), Own(metric.SessionAverageTime), Own(metric.PeakTime)))
	ns.Print(ns.L.cpuSpikes:format(Own(metric.CountTimeOver1Ms), Own(metric.CountTimeOver5Ms)))
	ns.Print(ns.L.cpuAll:format(profiler.GetOverallMetric(metric.RecentAverageTime) or 0,
		profiler.GetApplicationMetric(metric.RecentAverageTime) or 0))
end

-- The lines as the game writes them, in its font and spacing, to picture the
-- same lines before and after (/everchat plain): the choices it changes are
-- kept here and put back by running it again, or on a reload or logout.
local PLAIN = { chatFont = "game", fontOutline = "none", lineSpacing = "compact" }
local beforePlain

local function ApplyLook()
	ns.Fonts.Refresh()
	ns.Timestamps.ApplySpacing()
end

function ns.RestorePlain()
	if not beforePlain then
		return false
	end
	for key, value in pairs(beforePlain) do
		ns.db[key] = value
	end
	beforePlain = nil
	return true
end

local function TogglePlain()
	if ns.RestorePlain() then
		ApplyLook()
		ns.Lines.SetPlain(false)
		ns.Print(ns.L.plainOff)
		return
	end
	beforePlain = {}
	for key, value in pairs(PLAIN) do
		beforePlain[key] = ns.db[key]
		ns.db[key] = value
	end
	ApplyLook()
	ns.Lines.SetPlain(true)
	ns.Print(ns.L.plainOn)
end

SLASH_EVERCHAT1 = "/everchat"
SlashCmdList.EVERCHAT = function(input)
	local command = strtrim(input or ""):lower()
	if command == "reset" then
		ns.Resize.Forget()
		ns.Print(ns.L.layoutReset)
		return
	end
	if command == "font" or command == "fuente" then
		ns.Fonts.Report()
		return
	end
	if command == "cpu" then
		ReportCPU()
		return
	end
	if command == "plain" or command == "plano" then
		TogglePlain()
		return
	end
	if command == "font reset" or command == "fuente reset" then
		ns.Print(ns.L.fontReset:format(ns.Fonts.ResetSizes()))
		return
	end
	-- Diagnostic mode: Everchat leaves the chat windows' AddMessage alone
	-- (Lines, Alerts and History hook it), the one Blizzard method it hooks.
	-- With the game's taint log on (/console taintLog 1), Blizzard's own calls
	-- to a hooked AddMessage fail ("attempt to call a nil value"), so this is
	-- how a taint log can still be taken. Applies on the reload it triggers.
	if command == "diag" then
		ns.db.diag = not ns.db.diag or nil
		ReloadUI()
		return
	end
	if CLEAR_HISTORY[command] then
		ns.History.Clear()
		ns.Print(ns.L.historyCleared)
		return
	end

	local toggle = TOGGLES[command]
	if not toggle then
		-- Bare /everchat opens the options page; anything else lists the commands.
		if command == "" then
			ns.Options.Open()
		else
			ns.Print("v" .. ns.version .. " - /everchat time | emblem | channels | history | history clear | font | font reset | cpu | plain | reset | diag")
		end
		return
	end

	ns.db[toggle.key] = not ns.db[toggle.key]
	ns.Print(toggle.label .. " " .. (ns.db[toggle.key] and "on" or "off") .. ".")
	if toggle.after then
		toggle.after()
	end
end
