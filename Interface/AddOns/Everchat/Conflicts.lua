local _, ns = ...

local Conflicts = {}
ns.Conflicts = Conflicts

-- Other addons that restyle the chat change the same frames as Everchat, and
-- some taint the secure code around it (Prat-3.0's taint surfaced as Lua
-- errors in Blizzard's party frames on leaving Edit Mode). When one is
-- loaded, a dialog asks which to keep: disabling either (for this character,
-- as the game's own addon list does in game) and reloading, or keeping both.
-- Keeping both is remembered per character. The dialog is Everchat's own
-- frame: adding to Blizzard's StaticPopup system from an addon can taint it.
--
-- Besides the known ones, any addon that replaced part of the chat's secure
-- code (a window's AddMessage, a ChatFrameUtil function, a channel label
-- string: what Prat does) is found by issecurevariable, which names it; those
-- are the ones that cause Lua errors elsewhere. Everchat's own hooks
-- (hooksecurefunc) leave all of these secure.
local KNOWN = {
	{ addon = "Prat-3.0" },
	{ addon = "Chatter" },
	{ addon = "Chattynator" },
	-- Glass Forever, a copy of Glass for Forever, has the same folder name.
	{ addon = "Glass" },
	{ addon = "BetterForeverChat" },
	-- ElvUI only clashes while its chat module is on.
	{
		addon = "ElvUI",
		active = function()
			local engine = ElvUI and ElvUI[1]
			return not (engine and engine.private and engine.private.chat and engine.private.chat.enable == false)
		end,
	},
}

local WIDTH = 360
local PADDING = 16
local BUTTON_GAP = 6
-- After the loading screen, so it isn't lost behind it.
local SHOW_DELAY = 2

local L = ns.L

local function CharacterKey()
	return ns.CharacterKey()
end

local function IsKept(addon)
	local kept = ns.db.keptConflicts and ns.db.keptConflicts[CharacterKey()]
	return kept and kept[addon]
end

local function Keep(addon)
	ns.db.keptConflicts = ns.db.keptConflicts or {}
	local key = CharacterKey()
	ns.db.keptConflicts[key] = ns.db.keptConflicts[key] or {}
	ns.db.keptConflicts[key][addon] = true
end

-- Global strings secure chat code formats lines with.
local CHANNEL_LABELS = {
	"CHAT_SAY_GET", "CHAT_YELL_GET", "CHAT_WHISPER_GET", "CHAT_WHISPER_INFORM_GET",
	"CHAT_GUILD_GET", "CHAT_OFFICER_GET", "CHAT_PARTY_GET", "CHAT_PARTY_LEADER_GET",
	"CHAT_RAID_GET", "CHAT_RAID_LEADER_GET", "CHAT_RAID_WARNING_GET",
	"CHAT_INSTANCE_CHAT_GET", "CHAT_INSTANCE_CHAT_LEADER_GET",
}

-- ChatFrameUtil functions off the path messages take, which other kinds of
-- addons replace with no harm to the chat: the /played output, which Titan
-- Panel, AllTheThings and the like silence while they ask for the time
-- played.
local HARMLESS = { DisplayTimePlayed = true }

-- The addon an insecure value came from, unless it's none or Everchat.
local function Owner(secure, owner)
	if not secure and owner and owner ~= "" and owner ~= "Everchat" then
		return owner
	end
	return nil
end

local function FindTaint()
	for _, name in pairs(CHAT_FRAMES) do
		local owner = Owner(issecurevariable(_G[name], "AddMessage"))
		if owner then
			return owner
		end
	end
	for key, value in pairs(ChatFrameUtil) do
		if type(value) == "function" and not HARMLESS[key] then
			local owner = Owner(issecurevariable(ChatFrameUtil, key))
			if owner then
				return owner
			end
		end
	end
	for _, label in ipairs(CHANNEL_LABELS) do
		local owner = Owner(issecurevariable(label))
		if owner then
			return owner
		end
	end
	return nil
end

-- An addon's title as the addon list shows it, without its color codes.
local function Title(addon)
	local _, title = C_AddOns.GetAddOnInfo(addon)
	title = (title or addon):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return title
end

local function FindConflict()
	for _, known in ipairs(KNOWN) do
		if C_AddOns.IsAddOnLoaded(known.addon) and not IsKept(known.addon)
			and (not known.active or known.active()) then
			-- Named as the addon list names it ("Glass Forever" in Glass's folder).
			return { addon = known.addon, name = Title(known.addon) }
		end
	end
	local owner = FindTaint()
	if owner and not IsKept(owner) then
		return { addon = owner, name = Title(owner) }
	end
	return nil
end

-- Disables an addon for this character and reloads (from a button click).
-- What the other addon left behind in Everchat's own data goes with it: its
-- override of the one-time font default (Prat sets every window's font to 12),
-- which applies again after the reload, and this character's saved chat,
-- saved with its formatting. Blizzard settings it changed stay: like ElvUI,
-- Everchat can't know what they were before (/resetchat resets the chat).
local function DisableAndReload(addon)
	C_AddOns.DisableAddOn(addon, UnitGUID("player"))
	if addon ~= "Everchat" then
		ns.Fonts.Rearm()
		ns.History.ClearCharacter()
	end
	ReloadUI()
end

-- In Everchat's window look, like the options window (Options.CreateWindow).
-- Its close button leaves the choice for the next login.
local function CreateDialog(conflict)
	local dialog = ns.Options.CreateWindow(WIDTH, L.conflictTitle)
	dialog:SetPoint("TOP", UIParent, "TOP", 0, -UIParent:GetHeight() / 4)

	local body = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	body:SetPoint("TOP", dialog, "TOP", 0, -(dialog.titleHeight + PADDING))
	body:SetWidth(WIDTH - 2 * PADDING)
	body:SetJustifyH("CENTER")
	body:SetText(L.conflictBody:format(conflict.name))

	local previous = body
	local buttonHeight = 0
	local function Button(text, onClick, silent)
		local button = ns.Options.CreateTextButton(dialog, text, onClick, false, silent)
		button:SetWidth(WIDTH - 2 * PADDING - 40)
		button:SetPoint("TOP", previous, "BOTTOM", 0, previous == body and -14 or -BUTTON_GAP)
		buttonHeight = button:GetHeight()
		previous = button
		return button
	end
	Button(L.conflictDisableOther:format(conflict.name), function()
		DisableAndReload(conflict.addon)
	end)
	Button(L.conflictDisableSelf, function()
		DisableAndReload("Everchat")
	end)
	-- Silent: the window sounds as it closes.
	Button(L.conflictKeepBoth, function()
		Keep(conflict.addon)
		dialog:Hide()
	end, true)

	-- Summed up: positions aren't resolved yet on the frame it's built.
	dialog:SetHeight(dialog.titleHeight + PADDING + body:GetStringHeight() + 14
		+ 3 * buttonHeight + 2 * BUTTON_GAP + PADDING)
	return dialog
end

-- Looked for a little after login, once other addons have set themselves up.
function Conflicts.Init()
	C_Timer.After(SHOW_DELAY, function()
		local conflict = FindConflict()
		if conflict then
			CreateDialog(conflict):Show()
		end
	end)
end
