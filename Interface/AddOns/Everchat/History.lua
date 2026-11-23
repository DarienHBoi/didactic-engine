local _, ns = ...

local History = {}
ns.History = History

-- The chat survives reloads and logins: each window's messages are kept per
-- character in EverchatDB.history and added back when the game loads, with
-- their own times (Timestamps) and without lighting tabs (Alerts).
--
-- It can be turned off (/everchat history), which also deletes what's saved,
-- and cleared (/everchat history clear): whispers included, it's private chat
-- kept in a file on the player's computer.
--
-- Only the game's own chat messages are kept (AddMessage with an event):
-- never secret messages (they can't be read), Battle.net ones (their names are
-- per-session tokens that would come back as garbage), addon prints, the
-- combat log or temporary windows. Blizzard's own history table is never
-- touched: lines go back in through AddMessage, like any other.
-- Other chat addons keep 1,000 to 5,000 lines; 1,500 per window, at most a
-- day old, keeps a long scroll-back without a huge saved file or a slow login.
local MAX_LINES = 1500
-- Trim in batches rather than on every message.
local TRIM_SLACK = 50
local MAX_AGE = 24 * 60 * 60

-- Fields of a saved line.
local TIME, MESSAGE, RED, GREEN, BLUE, EVENT, SENDER = 1, 2, 3, 4, 5, 6, 7

local hooked = {}
-- The saved time of the line being added back, while replaying.
local replayTime

local function GetStore()
	local key = ns.CharacterKey()
	ns.db.history = ns.db.history or {}
	ns.db.history[key] = ns.db.history[key] or {}
	return ns.db.history[key]
end

local function IsKept(chatFrame)
	return chatFrame ~= COMBATLOG and not chatFrame.isTemporary
		and chatFrame:GetID() <= Constants.ChatFrameConstants.MaxChatWindows
end

function History.ReplayTime()
	return replayTime
end

local function Accessible(value)
	return value == nil or not canaccessvalue or canaccessvalue(value)
end

local function OnAddMessage(chatFrame, message, r, g, b, _, _, _, event, eventArgs)
	if not ns.db.keepHistory or replayTime then
		return
	end
	if type(event) ~= "string" or strsub(event, 1, 12) == "CHAT_MSG_BN_" then
		return
	end
	if type(message) ~= "string" or not Accessible(message) or message:find("|K", 1, true) or ns.Lines.IsBlank(message) then
		return
	end
	if not (Accessible(r) and Accessible(g) and Accessible(b)) then
		return
	end

	local store = GetStore()
	local id = chatFrame:GetID()
	local lines = store[id]
	if not lines then
		lines = {}
		store[id] = lines
	end
	-- The sender's GUID (when readable): lines brought back keep their marks
	-- and their name's tooltip (Players.lua).
	local guid = eventArgs and eventArgs[12]
	if guid ~= nil and not (Accessible(guid) and type(guid) == "string" and guid ~= "") then
		guid = nil
	end
	table.insert(lines, { time(), message, r, g, b, event, guid })
	if #lines > MAX_LINES + TRIM_SLACK then
		-- A copy of the newest MAX_LINES (no unpack: too many values).
		local kept = {}
		for index = #lines - MAX_LINES + 1, #lines do
			kept[#kept + 1] = lines[index]
		end
		store[id] = kept
	end
end

-- Lines older than a day go for every character at login, not only this
-- one: a character that isn't played would otherwise keep its last day of
-- chat in the saved file for good, and the file grows with each alt.
local function PruneAll(cutoff)
	for key, store in pairs(ns.db.history or {}) do
		for id, lines in pairs(store) do
			local kept = {}
			for _, line in ipairs(lines) do
				if line[TIME] >= cutoff then
					kept[#kept + 1] = line
				end
			end
			store[id] = #kept > 0 and kept or nil
		end
		if next(store) == nil then
			ns.db.history[key] = nil
		end
	end
end

-- A saved line's kind of chat as the game colors it (ChatTypeInfo): its
-- event's ("GUILD", "WHISPER_INFORM"...), a numbered channel's by the number
-- in its link ("CHANNEL2"). A community's lines take their club's color.
local function ChatTypeOf(line)
	local chatType = strsub(line[EVENT], 10)
	if chatType == "COMMUNITIES_CHANNEL" then
		return nil
	end
	if strsub(chatType, 1, 7) == "CHANNEL" then
		local number = line[MESSAGE]:match("|Hchannel:%a*:?(%d+)|h")
		if number then
			return "CHANNEL" .. number
		end
	end
	return chatType
end

-- The game sets every chat type white until the player's chat colors load.
local function ColorsLoaded()
	for _, info in pairs(ChatTypeInfo) do
		if info.r ~= 1 or info.g ~= 1 or info.b ~= 1 then
			return true
		end
	end
	return false
end

-- Adds a window's saved lines back, oldest first, through AddMessage: the
-- other hooks see them as they did the first time (a fresh eventArgs table
-- stands in for the event's, which only Channels compares, by identity).
-- Each comes back in its kind's color as it is now (the one it was saved
-- with until the colors load) and with its kind's ID, which the game
-- recolors lines by when a color changes or loads (UpdateColorByID).
local function Restore(chatFrame, lines)
	local cutoff = time() - MAX_AGE
	local kept = {}
	for _, line in ipairs(lines) do
		if line[TIME] >= cutoff then
			table.insert(kept, line)
		end
	end
	local loaded = ColorsLoaded()
	for _, line in ipairs(kept) do
		local r, g, b = line[RED], line[GREEN], line[BLUE]
		local info = ChatTypeInfo[ChatTypeOf(line) or ""]
		if info and loaded then
			r, g, b = info.r, info.g, info.b
		end
		replayTime = line[TIME]
		chatFrame:AddMessage(line[MESSAGE], r, g, b, info and info.id, nil, nil, line[EVENT], { [12] = line[SENDER] })
	end
	replayTime = nil
	return kept
end

local function Setup(chatFrame)
	if hooked[chatFrame] or not IsKept(chatFrame) or ns.db.diag then
		return
	end
	hooked[chatFrame] = true
	-- A public ScrollingMessageFrame setter: runs as a secure barrier. It keeps
	-- the lines already there.
	if chatFrame:GetMaxLines() < MAX_LINES then
		chatFrame:SetMaxLines(MAX_LINES)
	end
	hooksecurefunc(chatFrame, "AddMessage", OnAddMessage)
end

local function SetupAllChatFrames()
	for _, name in pairs(CHAT_FRAMES) do
		Setup(_G[name])
	end
end

-- Deletes every character's saved chat. What's on screen stays until reload.
function History.Clear()
	ns.db.history = nil
end

-- Deletes one window's saved chat (Buttons.lua's "Clear chat").
function History.ClearWindow(chatFrame)
	GetStore()[chatFrame:GetID()] = nil
end

-- Deletes this character's saved chat (Conflicts.lua: lines saved while
-- another chat addon was rewriting them carry its formatting, like Prat's
-- "[S]" and "[1:Name]", and would come back after it's gone).
function History.ClearCharacter()
	if ns.db.history then
		ns.db.history[ns.CharacterKey()] = nil
	end
end

-- After the other modules hook AddMessage, so the lines come back dressed.
function History.Init()
	if not ns.db.keepHistory then
		History.Clear()
	end
	PruneAll(time() - MAX_AGE)
	local store = GetStore()
	for id, lines in pairs(store) do
		local chatFrame = _G["ChatFrame" .. id]
		if chatFrame and IsKept(chatFrame) then
			store[id] = Restore(chatFrame, lines)
		else
			store[id] = nil
		end
	end
	SetupAllChatFrames()
	hooksecurefunc("FCF_OpenNewWindow", SetupAllChatFrames)
	-- A closed window's ID may come back as another window.
	hooksecurefunc("FCF_Close", function(frame, fallback)
		local closed = fallback or frame or FCF_GetCurrentChatFrame()
		if closed then
			GetStore()[closed:GetID()] = nil
		end
	end)
end
