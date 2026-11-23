local _, ns = ...
local Theme = ns.Theme

local Timestamps = {}
ns.Timestamps = Timestamps

-- Every message starts with its time, in a muted grey, where the game's own
-- timestamps go: always there, so each line says when it was written and a
-- pause shows as a jump in the times. (v0.26.0; before, only the first message
-- of each minute had it, and a divider marked long pauses: the user found it
-- ambiguous which lines a time belonged to.)
-- In the game clock's own format (the 24-hour clock option, and its
-- localized AM/PM otherwise).
local TIME_SEPARATOR = "  "

local function FormatClock(clock)
	local fields = date("*t", clock)
	if GameTime_GetFormattedTime then
		return GameTime_GetFormattedTime(fields.hour, fields.min, true)
	end
	return date("%H:%M", clock)
end

-- The last minute formatted, for the lines that keep coming in it (the
-- 24-hour option can change between them).
local lastMinute, lastMilitary, lastText

local function FormatTime(clock)
	local minute = math.floor(clock / 60)
	local military = C_CVar.GetCVar("timeMgrUseMilitaryTime")
	if minute ~= lastMinute or military ~= lastMilitary then
		lastMinute, lastMilitary, lastText = minute, military, FormatClock(clock)
	end
	return lastText
end

-- A line's day and time for its time's tooltip (Links.lua), the day as the
-- game's calendar writes it ("Saturday, October 10"): History brings lines
-- back from the day before, whose time alone doesn't say which day.
function Timestamps.FullDate(clock)
	local fields = date("*t", clock)
	local day = CalendarUtil and CalendarUtil.FormatCalendarTimeWeekday
		and CalendarUtil.FormatCalendarTimeWeekday({ weekday = fields.wday, month = fields.month, monthDay = fields.day })
	return day and (day .. ", " .. FormatTime(clock)) or FormatTime(clock)
end

-- Line spacing (Options > Appearance, 2026-10-13, the user's call; Better
-- Forever Chat offers it too): the space between the wrapped lines of a
-- message (the frame's own spacing, a secure ScrollingMessageFrame setter,
-- over what it has on load) and the extra air between messages, in units.
-- "normal" is what Everchat always drew (v0.26.0's gap of 3), "compact" the
-- game's own; the combat log keeps the game's.
local SPACINGS = {
	compact = { lines = 0, messages = 0 },
	normal = { lines = 0, messages = 3 },
	wide = { lines = 2, messages = 6 },
}

local function Spacing()
	return SPACINGS[ns.db.lineSpacing] or SPACINGS.normal
end

-- Chat frames set up, each with the spacing it had on load; never marked on
-- Blizzard frames.
local states = {}

-- Whether the game's own timestamps are on (Options > Social). Read from the
-- CVar: the Settings value ChatFrameUtil.GetTimestampFormat reads isn't loaded
-- yet for the first lines after login, which then got both times.
function Timestamps.GameShowsTimes()
	local value = C_CVar.GetCVar("showTimestamps")
	return value ~= nil and value ~= "" and value ~= "none"
end

local function IsEnabled()
	-- Defer to the game's own timestamps when the player has them enabled.
	return ns.db.timestamps and not Timestamps.GameShowsTimes()
end

local function Concat(prefix, message)
	return prefix .. message
end

local greyCode

-- The time's grey as a color code (notices take it too, Channels.lua).
function Timestamps.GreyCode()
	greyCode = greyCode or ("|cff%02x%02x%02x"):format(Theme.TIME.r * 255, Theme.TIME.g * 255, Theme.TIME.b * 255)
	return greyCode
end

local function Grey(text)
	return Timestamps.GreyCode() .. text .. "|r"
end

-- A line with its time in front (Lines.lua), or as it is while the times are
-- off. Concatenating works for secret messages too; if it ever fails, the
-- line is left as it is.
-- With `lineID` (Lines.lua, readable lines only) the time is a link: clicking
-- it opens the line as text, ready to copy (Links.lua), as BasicChatMods and
-- Prat let players do.
local LINE_LINK = "|Haddon:Everchat:line:%d|h%s|h"

function Timestamps.Prefix(text, clock, lineID)
	if not IsEnabled() then
		return text
	end
	local time = Grey(FormatTime(clock))
	if lineID then
		time = LINE_LINK:format(lineID, time)
	end
	local ok, prefixed = pcall(Concat, time .. TIME_SEPARATOR, text)
	return ok and prefixed or text
end

-- Blizzard shows one font string per message and chains each to the one below
-- in RefreshLayout; once the display is refreshed (which always follows a new
-- layout) they're re-anchored with more air between messages than between the
-- lines of one. The frame's own callback for addons (AddOnDisplayRefreshedCallback,
-- run through secureexecuterange) rather than a hook on its private methods.
-- Called with the window once its lines are in their places (Skin.lua).
local placedListeners = {}

function Timestamps.OnLinesPlaced(listener)
	table.insert(placedListeners, listener)
end

local function OnDisplayRefreshed(chatFrame)
	local lines = chatFrame.visibleLines
	local fromTop = chatFrame:GetInsertMode() == SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP
	for index = 2, #lines do
		local line, previous = lines[index], lines[index - 1]
		local gap = line:GetSpacing() + Spacing().messages
		if fromTop then
			line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -gap)
		else
			line:SetPoint("BOTTOMLEFT", previous, "TOPLEFT", 0, gap)
		end
	end
	for _, listener in ipairs(placedListeners) do
		listener(chatFrame)
	end
end

local function Setup(chatFrame)
	-- The combat log has its own timestamp option.
	if states[chatFrame] or chatFrame == COMBATLOG then
		return
	end

	states[chatFrame] = chatFrame:GetSpacing() or 0

	-- Wrapped lines start flush with the message.
	if chatFrame:GetIndentedWordWrap() then
		chatFrame:SetIndentedWordWrap(false)
	end
	if Spacing().lines ~= 0 then
		chatFrame:SetSpacing(states[chatFrame] + Spacing().lines)
	end
	chatFrame:AddOnDisplayRefreshedCallback(OnDisplayRefreshed)
	chatFrame:MarkLayoutDirty()
end

local function SetupAllChatFrames()
	for _, name in pairs(CHAT_FRAMES) do
		Setup(_G[name])
	end
end

-- Call after turning the times on or off: every line is composed again.
function Timestamps.Refresh()
	ns.Lines.Refresh()
end

-- Call after changing the line spacing: every window lays its lines out
-- again (the display refresh re-anchors the messages with the new air), and
-- what was measured on them goes.
function Timestamps.ApplySpacing()
	for chatFrame, base in pairs(states) do
		chatFrame:SetSpacing(base + Spacing().lines)
		chatFrame:MarkLayoutDirty()
		ns.Fonts.Changed(chatFrame)
	end
end

function Timestamps.Init()
	SetupAllChatFrames()
	hooksecurefunc("FCF_OpenNewWindow", SetupAllChatFrames)
	hooksecurefunc("FCF_OpenTemporaryWindow", SetupAllChatFrames)
end
