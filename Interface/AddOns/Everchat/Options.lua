local _, ns = ...
local Theme = ns.Theme

local Options = {}
ns.Options = Options

-- Everchat's options in a window of its own (2026-10-12, the user's call,
-- after Baganator's), in the chat's look: the card, the header strip with
-- its gold trim, page tabs like the chat's with the gold frame on the open
-- one, the game's fonts for the text and Blizzard's own menus for the lists.
-- Its own because the game's settings can't hold per-tab choices: proxy
-- settings (one per window, with our functions for name and value) tainted
-- Settings.GetValue, which action buttons read on every click, and the game
-- blocked UseAction (v0.33.0, taint.log at Blizzard_SettingsPanel.lua:780).
-- These frames only read and write EverchatDB; whatever needs more than the
-- stored value (refreshing the chat's lines, the rail, deleting the saved
-- history) runs when a box is clicked. The game's settings keep an Everchat
-- page whose only button opens this window (Options > AddOns), added
-- through Blizzard's secure delegate (Settings.RegisterInitializer).
-- Pages: Appearance (the font, the time, icons and marks, each tab's font
-- size), Messages (what the lines say and do), Channels (each label's icon,
-- name and color), Alerts (the player's name, quiet, each tab's visual and
-- audio alerts and its sound), Buttons (the side rail) and History and tabs.
local L = ns.L
local MEDIA = "Interface\\AddOns\\Everchat\\Media\\"

-- Wide enough for a row of the tabs table: two boxes, the tab's sound
-- between its arrows and the button to hear it.
local WIDTH = 630
local PAD_X = 18
local PAD_TOP = 8
local PAD_BOTTOM = 16
-- Rows and columns as in the game's own settings (Blizzard_SettingControls):
-- the label on the left in the game's gold, never wrapped, the control in a
-- column of its own, the whole row lit (white 10%) under the mouse.
local ROW = 30
local LABEL_X = 10
local CONTROL_X = 250
local SECTION_HEIGHT = 38
local BUTTON_WIDTH = 180
local CONTROL_HEIGHT = 26
-- The tabs table's second column, after the first box.
local SECOND_COLUMN = 64
-- The logo, in screen pixels (times the art's scale on dense screens).
local LOGO_PIXELS = 20
-- The close button, in screen pixels (times the art scale).
local CLOSE_PIXELS = 26
local CLOSE_DESATURATION = 0.85
local TAB_PADDING = 14
-- The title bar over the page tabs (Baganator's layout; 2026-10-12, the user:
-- the logo and name beside the close button crowded the tabs' row), and
-- where the first tab starts.
-- Both set in whole screen pixels when the window is made (CreateWindow): at
-- 1.2 pixels a unit, 54 units fell between pixel rows, and the line under
-- the page tabs sat a pixel above the open tab's sides.
local TITLE_BAR = 28
local TITLE_HEIGHT = TITLE_BAR
local TABS_X = 8
-- The page tabs' row, as tall as the game's chat dock: roomier than the
-- chat's header, for the window's larger panel font.
local TAB_ROW = 26
local TOP = TITLE_BAR + TAB_ROW
local WINDOW_ALPHA = 0.95
-- A dropdown's width, the game's settings' own (the longest font name, in
-- its own font, whole); the tabs table's sound dropdown is narrower, after its
-- box, and its row ends with the button to hear it.
local DROPDOWN_WIDTH = 220
local SOUND_DROP_WIDTH = 156
-- Air between the box and the sound's control (at 4 they looked stuck together).
local SOUND_DROP_GAP = 10
-- A dropdown's menu scrolls past this many of the game's entries (20 tall).
local MENU_ROWS = 20
-- The arrows on either side of a dropdown (SteppersIncrementButtonTemplate)
-- and the air the template leaves between each and the dropdown.
local STEPPER_WIDTH = 26
local STEPPER_GAP_LEFT = 5
local STEPPER_GAP_RIGHT = 4

local window
local pages, pageTabs = {}, {}
-- The gold line under the page tabs, open under the open one (Skin.lua).
local tabLine
local current = 1
local category
local keyboardArmed = false

-- Everchat's small tooltip (Links.lua).
local function HideTip(owner)
	ns.Links.HideSmallTip(owner)
end

-- A stored option's value, the default while it has none.
local function Get(key)
	local value = ns.db[key]
	if value == nil then
		value = ns.defaults[key]
	end
	return value
end

-- A page: a frame under the header and a cursor going down it. Builders add
-- rows at the cursor; refreshers put the stored values back on show.
local function NewPage(title)
	local frame = CreateFrame("Frame", nil, window)
	frame:SetPoint("TOPLEFT", window, "TOPLEFT", PAD_X, -(TOP + PAD_TOP))
	frame:SetPoint("RIGHT", window, "RIGHT", -PAD_X, 0)
	frame:SetHeight(1)
	frame:Hide()
	local page = { frame = frame, title = title, y = 0, extra = 0, refreshers = {}, width = WIDTH - 2 * PAD_X }
	table.insert(pages, page)
	return page
end

-- A section's title, as the game's settings write theirs.
local function Section(page, text)
	local title = page.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("BOTTOMLEFT", page.frame, "TOPLEFT", 0, page.y - SECTION_HEIGHT + 8)
	title:SetText(text)
	page.y = page.y - SECTION_HEIGHT
end

-- A section's description in grey under its title, as the game's settings
-- describe a page (LANGUAGES_SUBTEXT under "Languages"): what a group of
-- boxes does, said once, so each box needs only its own word.
local function Hint(page, text)
	local hint = page.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hint:SetTextColor(Theme.TIME:GetRGB())
	hint:SetJustifyH("LEFT")
	hint:SetWidth(page.width - 2 * LABEL_X)
	hint:SetPoint("TOPLEFT", page.frame, "TOPLEFT", LABEL_X, page.y)
	hint:SetText(text)
	page.y = page.y - math.ceil(hint:GetStringHeight()) - 6
end

-- A row as the game's settings build theirs (SettingsListElementTemplate):
-- only its label's part (`row.hit`, from its left to the control column) and
-- its controls take the mouse, nothing past them (lit to the right of a box,
-- the tooltip jumped between the row and the box, the user, 2026-10-12).
local function NewRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW)
	row:SetPoint("RIGHT", parent, "RIGHT")
	local hover = row:CreateTexture(nil, "BACKGROUND")
	hover:SetColorTexture(1, 1, 1, 0.1)
	hover:SetPoint("TOPLEFT", row, "TOPLEFT", -10, 0)
	hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 5, 0)
	hover:Hide()
	row.hover = hover
	local hit = CreateFrame("Button", nil, row)
	hit:SetPoint("TOPLEFT")
	hit:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", CONTROL_X, 0)
	row.hit = hit
	return row
end

local function Row(page)
	local row = NewRow(page.frame)
	row:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, page.y)
	page.y = page.y - ROW
	return row
end

-- The tooltip as the game's settings show theirs (DefaultTooltipMixin and
-- Settings.CreateOptionsInitTooltip in Blizzard_Settings): at the game's
-- size, just above what the mouse is on, from its right edge less 10 (a
-- checkbox's own edge), so over the label it starts by the control column;
-- the option's name in white over its sentence in gold, then, for a dropdown
-- whose choices have a few words each, a blank line and each choice's name
-- in white before its words. A tooltip may be a function returning it.
local function ShowRowTip(row, region, tooltip)
	if type(tooltip) == "function" then
		tooltip = tooltip()
	end
	if not tooltip then
		return
	end
	local lines = {}
	if row.labelText then
		table.insert(lines, { row.labelText, HIGHLIGHT_FONT_COLOR })
	end
	table.insert(lines, { tooltip, NORMAL_FONT_COLOR, true })
	for _, choice in ipairs(row.choices or {}) do
		if choice[3] then
			table.insert(lines, { " ", NORMAL_FONT_COLOR })
			table.insert(lines, { HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(choice[2]) .. ": " .. choice[3], NORMAL_FONT_COLOR, true })
		end
	end
	local x = region:GetObjectType() == "CheckButton" and 0 or -10
	ns.Links.ShowTip(region, "ANCHOR_RIGHT", lines, x, 0)
end

-- The row's label part and the controls given show the tooltip; the label
-- part and checkboxes light the whole row (white 10%, the game's
-- HoverBackgroundTemplate), buttons and dropdowns keep their own highlight.
local function Hover(row, tooltip, ...)
	for _, region in ipairs({ row.hit, ... }) do
		local lights = region == row.hit or region:GetObjectType() == "CheckButton"
		region:HookScript("OnEnter", function()
			if lights then
				row.hover:Show()
			end
			ShowRowTip(row, region, tooltip)
		end)
		region:HookScript("OnLeave", function()
			row.hover:Hide()
			HideTip(region)
		end)
	end
end

-- The row's name in the game's gold, never wrapped, in the label column.
local function Label(row, text, icon)
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	label:SetPoint("RIGHT", row, "LEFT", CONTROL_X - 12, 0)
	if icon then
		local picture = ns.Buttons.CreatePicture(row, icon)
		picture:SetPoint("LEFT", row, "LEFT", LABEL_X, 0)
		label:SetPoint("LEFT", picture, "RIGHT", 8, 0)
	else
		label:SetPoint("LEFT", row, "LEFT", LABEL_X, 0)
	end
	label:SetText(text)
	row.labelText = text
	return label
end

-- The game's own checkbox (its settings' art: a dark box, a gold check).
local function CreateBox(parent)
	return CreateFrame("CheckButton", nil, parent, "MinimalCheckboxTemplate")
end

-- An option's row: its name, its box. Clicking its name works like the box.
-- `onChanged` runs after the value is stored. With `icon`, a picture of the
-- rail button it switches stands before its name. With `inverted`, the box
-- is ticked while the stored switch is off (a stored "hide" shown as "show").
local function Check(page, key, label, tooltip, onChanged, icon, inverted)
	local row = Row(page)
	Label(row, label, icon)
	local box = CreateBox(row)
	box:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)
	box:SetScript("OnClick", function(self)
		local checked = self:GetChecked() and true or false
		Theme.PlayCheck(checked)
		if inverted then
			checked = not checked
		end
		ns.db[key] = checked
		if onChanged then
			onChanged(ns.db[key])
		end
	end)
	row.hit:SetScript("OnClick", function()
		box:Click()
	end)
	Hover(row, tooltip, box)
	table.insert(page.refreshers, function()
		local on = Get(key) and true or false
		box:SetChecked(on ~= (inverted and true or false))
	end)
end

-- A button with the game's own art (the three-slice "128-RedButton" its
-- panels use, Forever's own member), desaturated and tinted warm: the game's
-- bevelled metal frame around a dark fill, the label in the game's gold
-- (2026-10-12, the user: the game's button texture, our colors; a flat
-- button of our own looked like a web page's). The template swaps its art
-- on every state change; the tint goes back on each time.
local BUTTON_TINT = { 1, 0.84, 0.62 }

local function TintButton(button)
	for _, texture in ipairs({ button.Left, button.Center, button.Right, button:GetHighlightTexture() }) do
		texture:SetDesaturated(true)
		texture:SetVertexColor(unpack(BUTTON_TINT))
	end
end

-- With `silent`, the click makes no sound of its own (it opens a window,
-- which sounds as it opens).
local function CreateTextButton(parent, text, onClick, large, silent)
	local button = CreateFrame("Button", nil, parent, large and "SharedButtonLargeTemplate" or "SharedButtonSmallTemplate")
	button:SetText(text)
	if large then
		button:SetSize(math.max(220, button:GetFontString():GetStringWidth() + 64), 32)
	else
		button:SetSize(math.max(BUTTON_WIDTH, button:GetFontString():GetStringWidth() + 40), CONTROL_HEIGHT)
	end
	for _, script in ipairs({ "OnShow", "OnEnable", "OnDisable", "OnMouseDown", "OnMouseUp", "OnSizeChanged" }) do
		button:HookScript(script, TintButton)
	end
	TintButton(button)
	button:SetScript("OnClick", function(...)
		if not silent then
			Theme.PlaySound("button")
		end
		onClick(...)
	end)
	return button
end

-- The game's settings control (SettingsDropdownWithButtonsTemplate): its
-- dropdown, the choice in gold, between two arrows that step through the
-- choices without opening the menu, each click with the game's own sound. The
-- menu's entries are the settings' (CreateHighlightRadio: the chosen one in
-- gold, the others lit under the mouse), one per choice ({ value, text }), a
-- `{ title = text }` opening a group of them under a line; `choices` may be
-- a function returning them, asked each time the menu opens. `get` returns
-- the value chosen, `set` stores one, `decorate(radio, value)` may add to an
-- entry. `get` is asked at once: setting a menu up builds it.
-- The template centers its dropdown and hangs the arrows from it; here the
-- dropdown is set at the control's left, so arrows and dropdown fill the
-- control's width exactly. Returns the dropdown and the control around it.
local function CreateDropdown(row, choices, get, set, decorate, width)
	width = width or DROPDOWN_WIDTH
	local control = CreateFrame("Frame", nil, row, "SettingsDropdownWithButtonsTemplate")
	control:SetSize(STEPPER_WIDTH + STEPPER_GAP_LEFT + width + STEPPER_GAP_RIGHT + STEPPER_WIDTH, CONTROL_HEIGHT)
	local dropdown = control.Dropdown
	dropdown:SetWidth(width)
	dropdown:ClearAllPoints()
	dropdown:SetPoint("LEFT", control, "LEFT", STEPPER_WIDTH + STEPPER_GAP_LEFT, 0)
	-- With no choice marked (a value the list hasn't, or "Varios" while the
	-- tabs' sizes differ) the arrows would step from the list's end; there is
	-- nothing to step from, so both rest.
	local SetSteppersEnabled = control.SetSteppersEnabled
	function control:SetSteppersEnabled(canDecrement, canIncrement)
		local description = dropdown:GetMenuDescription()
		if not description or #MenuUtil.GetSelections(description) == 0 then
			canDecrement, canIncrement = false, false
		end
		SetSteppersEnabled(self, canDecrement, canIncrement)
	end
	local function IsSelected(value)
		return get() == value
	end
	-- The arrows follow the choice (the game's settings build their dropdown
	-- again on every change).
	local function Select(value)
		set(value)
		dropdown:Update()
	end
	dropdown:SetupMenu(function(_, root)
		-- Only scrolls when the list is longer.
		root:SetScrollMode(MENU_ROWS * 20)
		for _, choice in ipairs(type(choices) == "function" and choices() or choices) do
			if choice.title then
				root:CreateDivider()
				root:CreateTitle(choice.title)
			else
				local radio = root:CreateHighlightRadio(choice[2], IsSelected, Select, choice[1])
				if decorate then
					decorate(radio, choice[1])
				end
			end
		end
	end)
	return dropdown, control
end

-- A choice of a few: its name and the game's dropdown, between its arrows,
-- in the control column (the name names the thing, the dropdown its value:
-- "Surname: Initial"). A choice may carry a few words as its third field,
-- listed in the row's tooltip. Returns the dropdown.
local function Dropdown(page, label, tooltip, choices, get, set, decorate)
	local row = Row(page)
	row.choices = type(choices) == "table" and choices or nil
	Label(row, label)
	local dropdown, control = CreateDropdown(row, choices, get, set, decorate)
	control:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)
	Hover(row, tooltip, dropdown)
	-- The dropdown shows the chosen value once its menu is built.
	table.insert(page.refreshers, function()
		dropdown:GenerateMenu()
	end)
	return dropdown, control
end

-- A choice stored under `key`; `onChanged` runs after the value is stored.
local function Choice(page, key, label, tooltip, choices, onChanged)
	return Dropdown(page, label, tooltip, choices, function()
		return Get(key)
	end, function(value)
		ns.db[key] = value
		if onChanged then
			onChanged(value)
		end
	end)
end

-- The chat's font as a choice that names it (the label names the thing, the
-- dropdown its value, as for the surname; a box "Everchat's font" until
-- 2026-10-13): Everchat's fonts and the game's by their names, as font lists
-- in the game's addons name them, then those other addons share
-- (SharedMedia), each in its own font, in the menu and on the dropdown, as
-- font pickers show them. The shared ones are listed afresh each time the
-- menu opens, and the tooltip names them only while there are some.
local SHARED_MEDIA = "SharedMedia"

local function FontChoices()
	local choices = {}
	for _, font in ipairs(ns.Fonts.FONTS) do
		table.insert(choices, { font.key, font.label })
	end
	table.insert(choices, { "game", ns.Fonts.GameFontName() })
	local shared = ns.Fonts.Shared()
	if #shared > 0 then
		table.insert(choices, { title = SHARED_MEDIA })
		for _, font in ipairs(shared) do
			table.insert(choices, { font.key, font.label })
		end
	end
	return choices
end

local function FontTip()
	return #ns.Fonts.Shared() > 0 and L.optionFontSharedTip or L.optionFontTip
end

local function FontChoice(page)
	local dropdown
	local function ShowFont()
		dropdown.Text:SetFontObject(ns.Fonts.Sample(ns.Fonts.Current()))
	end
	dropdown = Dropdown(page, L.optionFont, FontTip, FontChoices, ns.Fonts.Current, function(key)
		ns.db.chatFont = key
		ns.Fonts.Refresh()
		ShowFont()
	end, function(radio, key)
		radio:AddInitializer(function(button)
			local text = button.Text
			if text then
				-- The menu's text lines are pooled and get the menu's font back
				-- when released (Blizzard_Menu's Compositor), so this one stays
				-- here. Measured again in its font, with the room the game's
				-- entries keep after their text, and the entry sized to it.
				text:SetFontObject(ns.Fonts.Sample(key))
				text:SetTextToFit(text:GetText())
				text:SetWidth(text:GetWidth() + 45)
				button:Layout()
			end
		end)
	end)
	table.insert(page.refreshers, ShowFont)
end

-- A row with a button in the control column. With `opens`, the button opens
-- a window, whose own sound is the click's.
local function Action(page, label, buttonText, onClick, tooltip, opens)
	local row = Row(page)
	Label(row, label)
	local button = CreateTextButton(row, buttonText, onClick, false, opens)
	button:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)
	Hover(row, tooltip, button)
end

-- A sound in the dropdown's menu: its name, and a class sound's class first,
-- in the game's own word for it and its color ("Mage: Frost Nova").
local SOUND_LABELS = {}
for _, sound in ipairs(ns.Alerts.SOUNDS) do
	SOUND_LABELS[sound.key] = sound.label
end

local function SoundEntryText(sound)
	if not sound.class then
		return sound.label
	end
	local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[sound.class] or sound.class
	local color = C_ClassColor and C_ClassColor.GetClassColor(sound.class)
	if color then
		name = color:WrapTextInColorCode(name)
	end
	return name .. ": " .. sound.label
end

-- The game's own way to hear a sound before choosing it (the cooldown
-- manager's alert sounds, Blizzard_CooldownViewer): a speaker on each entry
-- of the menu, shown under the mouse, that plays the sound without choosing
-- it, "Play Sample" in its tooltip, in the gold speaker the game's sound
-- dropdowns use (2026-10-12: the user found trying sounds tiresome when each
-- pick closed the menu; the references agree on a preview kept apart from
-- the choice).
local SPEAKER_PIXELS = 17
local PLAY_SAMPLE = COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_PLAY_SAMPLE or L.playSample

local function SpeakerAtlas(region)
	local px = PixelUtil.ConvertPixelsToUIForRegion(1, region)
	return math.ceil(1 / px - 0.5) >= 2 and "common-dropdown-icon-sound-on-2x" or "common-dropdown-icon-sound-on"
end

-- The speaker's target: its zone is wider than the icon and always shown
-- (dim until the mouse is on it), reaching a few units towards the name, so
-- a click just short of the icon plays instead of choosing (2026-10-12, the
-- user: the small speaker that only showed under the mouse was easy to miss,
-- and a miss chose the sound).
local SPEAKER_ZONE = 26
local SPEAKER_REACH = 6
local SPEAKER_REST = 0.55

local function AddSpeaker(button, key)
	-- In the room the game's entries keep after their text for an icon at
	-- the right (CreateHighlightRadio), so it never covers the longest name.
	local speaker = MenuTemplates.AttachBasicButton(button, SPEAKER_ZONE, 20)
	speaker:SetPoint("RIGHT", button, "RIGHT")
	speaker:SetHitRectInsets(-SPEAKER_REACH, 0, 0, 0)
	speaker:SetNormalAtlas(SpeakerAtlas(button))
	local icon = speaker:GetNormalTexture()
	local size = ns.Shapes.ArtPixels(button, SPEAKER_PIXELS)
	icon:ClearAllPoints()
	icon:SetPoint("CENTER")
	icon:SetSize(size, size)
	icon:SetAlpha(SPEAKER_REST)
	MenuTemplates.SetUtilityButtonTooltipText(speaker, PLAY_SAMPLE)
	speaker:HookScript("OnEnter", function()
		icon:SetAlpha(1)
	end)
	speaker:HookScript("OnLeave", function()
		icon:SetAlpha(SPEAKER_REST)
	end)
	MenuTemplates.SetUtilityButtonClickHandler(speaker, function()
		ns.Alerts.Preview(key)
	end)
end

-- A sound's dropdown, between its arrows, and the button to hear it, after
-- the box that turns it on, laid out like the game's checkbox-and-dropdown
-- settings (SettingsCheckboxDropdownControlTemplate): greyed while off,
-- keeping its choice. `get` and `set` read and store the choice. Returns the
-- dropdown and the control around it (the arrows grey with it).
local function SoundPicker(row, box, get, set)
	local control = CreateFrame("Frame", nil, row, "SettingsDropdownWithButtonsTemplate")
	control:SetSize(STEPPER_WIDTH + STEPPER_GAP_LEFT + SOUND_DROP_WIDTH + STEPPER_GAP_RIGHT + STEPPER_WIDTH, CONTROL_HEIGHT)
	control:SetPoint("LEFT", box, "RIGHT", SOUND_DROP_GAP, 0)
	local dropdown = control.Dropdown
	dropdown:SetWidth(SOUND_DROP_WIDTH)
	dropdown:ClearAllPoints()
	dropdown:SetPoint("LEFT", control, "LEFT", STEPPER_WIDTH + STEPPER_GAP_LEFT, 0)
	local function IsSelected(key)
		return get() == key
	end
	-- Picking a sound chooses it (and plays it) and closes the menu, as the
	-- game's dropdowns do; each entry's speaker only plays it (above). The
	-- arrows go through every list, playing each sound as they pass.
	local function SetSelected(key)
		set(key)
		dropdown:Update()
		ns.Alerts.Preview(key)
	end
	-- The button shows the sound's own name (without its class).
	dropdown:SetSelectionTranslator(function(selection)
		return SOUND_LABELS[selection.data] or MenuUtil.GetElementText(selection)
	end)
	dropdown:SetupMenu(function(_, root)
		-- A submenu per group, like the game's Font Size in the tab menu: the
		-- whole list in one menu ran most of the screen's height (2026-10-12,
		-- the user, thinking of smaller screens). The button still shows the
		-- choice: Blizzard's selection search goes into submenus.
		for _, group in ipairs(ns.Alerts.SOUND_GROUPS) do
			local submenu = root:CreateButton(group.label)
			for _, sound in ipairs(ns.Alerts.SOUNDS) do
				if sound.group == group.key then
					local radio = submenu:CreateHighlightRadio(SoundEntryText(sound), IsSelected, SetSelected, sound.key)
					radio:AddInitializer(function(button)
						AddSpeaker(button, sound.key)
					end)
				end
			end
		end
		-- Sounds other addons share (SharedMedia packs, boss timers), set
		-- apart under a line, while there are any.
		local shared = ns.Alerts.SharedSounds()
		if #shared > 0 then
			root:CreateDivider()
			local submenu = root:CreateButton(SHARED_MEDIA)
			submenu:SetScrollMode(MENU_ROWS * 20)
			for _, sound in ipairs(shared) do
				local radio = submenu:CreateHighlightRadio(sound.label, IsSelected, SetSelected, sound.key)
				radio:AddInitializer(function(button)
					AddSpeaker(button, sound.key)
				end)
			end
		end
	end)

	-- The chosen sound's sample beside the dropdown, as character creation
	-- puts a play button beside its voice choice; it plays even while off, so
	-- a sound can be checked before turning it on.
	local play = CreateFrame("Button", nil, row)
	local size = ns.Shapes.ArtPixels(play, SPEAKER_PIXELS)
	play:SetSize(size, size)
	play:SetPoint("LEFT", control, "RIGHT", 6, 0)
	local atlas = SpeakerAtlas(play)
	play:SetNormalAtlas(atlas)
	play:SetHighlightAtlas(atlas, "ADD")
	play:GetHighlightTexture():SetAlpha(0.4)
	play:SetScript("OnEnter", function(self)
		ns.Links.ShowTip(self, "ANCHOR_RIGHT", { { PLAY_SAMPLE, HIGHLIGHT_FONT_COLOR } })
	end)
	play:SetScript("OnLeave", HideTip)
	play:SetScript("OnClick", function()
		ns.Alerts.Preview(get())
	end)
	return dropdown, control
end

-- The chat windows in use, in the strip's order, then any floating one,
-- with readable names (a whisper window's may be secret). The combat log has
-- no alerts, but has a font size.
local function ListWindows(withCombatLog)
	local list, listed = {}, {}
	local function Add(chatFrame)
		local tab = chatFrame and _G[chatFrame:GetName() .. "Tab"]
		if not tab or listed[chatFrame] or not (withCombatLog or ns.Alerts.Covers(chatFrame))
			or not (chatFrame.isDocked or chatFrame:IsShown()) then
			return
		end
		local label = tab:GetText()
		if type(label) == "string" and canaccessvalue(label) and label ~= "" then
			listed[chatFrame] = true
			table.insert(list, { chatFrame = chatFrame, name = label })
		end
	end
	for _, id in ipairs(ns.Header.Order()) do
		Add(_G["ChatFrame" .. id])
	end
	for _, name in ipairs(CHAT_FRAMES) do
		Add(_G[name])
	end
	return list
end

-- A box of the tabs table: the alert's name in white over its sentence, as
-- the other options' tooltips are, and the row lit.
local function BoxTip(row, box, title, text)
	box:HookScript("OnEnter", function()
		row.hover:Show()
		ns.Links.ShowTip(box, "ANCHOR_RIGHT", {
			{ title, HIGHLIGHT_FONT_COLOR },
			{ text, NORMAL_FONT_COLOR, true },
		}, 0, 0)
	end)
	box:HookScript("OnLeave", function()
		row.hover:Hide()
		HideTip(box)
	end)
end

-- Every alert of every tab in one table (2026-10-12, the user: a sound for
-- each tab in use, not only for a few kinds of message, all together): its
-- name, the visual alert's box, the audio alert's box with the tab's sound
-- after it; the same switches as its right-click menu. Last on its page: the
-- rows follow the tabs there are, live while the window is open.
local function TabsTable(page)
	local heads = CreateFrame("Frame", nil, page.frame)
	heads:SetHeight(16)
	heads:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, page.y)
	heads:SetPoint("RIGHT", page.frame, "RIGHT")
	local boxWidth = 30
	for index, text in ipairs({ L.optionsTabVisual, L.optionsTabAudio }) do
		local head = heads:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		head:SetTextColor(Theme.TIME:GetRGB())
		head:SetText(text)
		head:SetPoint("BOTTOM", heads, "BOTTOMLEFT", CONTROL_X + (index - 1) * SECOND_COLUMN + boxWidth / 2, 0)
	end
	page.y = page.y - 16

	-- The sound new whisper tabs start with, in the audio column, first: the
	-- game opens one per person, and a tab's own choice goes when it closes.
	local whisper = Row(page)
	Label(whisper, L.optionWhisperSound)
	local column = CreateFrame("Frame", nil, whisper)
	column:SetSize(30, CONTROL_HEIGHT)
	column:SetPoint("LEFT", whisper, "LEFT", CONTROL_X + SECOND_COLUMN, 0)
	local whisperDropdown = SoundPicker(whisper, column, ns.Alerts.GetWhisperSound, ns.Alerts.SetWhisperSound)
	Hover(whisper, L.optionWhisperSoundTip, whisperDropdown)
	table.insert(page.refreshers, function()
		whisperDropdown:GenerateMenu()
	end)
	local top = page.y

	local rows = {}
	-- The row knows its window before its dropdown is made: setting a
	-- dropdown's menu up builds it at once, and that reads the choice.
	local function CreateRow(chatFrame)
		local row = NewRow(page.frame)
		row.chatFrame = chatFrame
		row.name = Label(row, "")
		local visual = CreateBox(row)
		visual:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)
		visual:SetScript("OnClick", function(self)
			local on = self:GetChecked() and true or false
			Theme.PlayCheck(on)
			ns.Alerts.SetEnabled(row.chatFrame, on)
		end)
		local audio = CreateBox(row)
		audio:SetPoint("LEFT", row, "LEFT", CONTROL_X + SECOND_COLUMN, 0)
		local dropdown, control = SoundPicker(row, audio, function()
			return row.chatFrame and ns.Alerts.GetTabSound(row.chatFrame)
		end, function(key)
			if row.chatFrame then
				ns.Alerts.SetTabSound(row.chatFrame, key)
			end
		end)
		audio:SetScript("OnClick", function(self)
			local on = self:GetChecked() and true or false
			Theme.PlayCheck(on)
			ns.Alerts.SetSound(row.chatFrame, on)
			control:SetEnabled(on)
			if on then
				ns.Alerts.PlayTabSound(row.chatFrame)
			end
		end)
		Hover(row, nil)
		BoxTip(row, visual, L.tabNotify, L.tabNotifyTip)
		BoxTip(row, audio, L.tabSound, L.tabSoundTip)
		row.refresh = function()
			visual:SetChecked(ns.Alerts.IsEnabled(row.chatFrame) and true or false)
			local ringing = ns.Alerts.HasSound(row.chatFrame)
			audio:SetChecked(ringing)
			control:SetEnabled(ringing)
			-- The dropdown shows the tab's sound once its menu is built.
			dropdown:GenerateMenu()
		end
		return row
	end
	table.insert(page.refreshers, function()
		local windows = ListWindows()
		for index, entry in ipairs(windows) do
			local row = rows[index] or CreateRow(entry.chatFrame)
			rows[index] = row
			row.chatFrame = entry.chatFrame
			row.name:SetText(entry.name)
			row:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, top - (index - 1) * ROW)
			row.refresh()
			row:Show()
		end
		for index = #windows + 1, #rows do
			rows[index]:Hide()
		end
		page.extra = #windows * ROW
	end)
end

-- The channels page's columns: the box of the label's icon with the icon
-- beside it, the field for its own name, the swatch of its color (the
-- game's own controls: its checkbox, its input box, its color swatch).
local LABEL_ICON = 18
local NAME_X = CONTROL_X + SECOND_COLUMN + 6
local NAME_WIDTH = 150
local NAME_HEIGHT = 20
local NAME_OFF_ALPHA = 0.45
local COLOR_X = NAME_X + NAME_WIDTH + 22
-- A typed name shows in the chat this long after the last key.
local PREVIEW_DELAY = 0.3
-- The game's undo arrow (its "Revert" in the cooldown manager's settings,
-- a slot's undo in transmog), after the swatch; lit under the mouse.
local RESET_ATLAS = "common-icon-undo"
local RESET_SIZE = 18
local RESET_X = COLOR_X + 32
local RESET_GLOW = 0.35
-- The open window follows changes made elsewhere (QueueRefresh, below).
local QueueRefresh

-- A table's column heads, small and grey over their columns: { text, x,
-- point } (centered on x, or from x on the left with "BOTTOMLEFT").
local function Heads(page, columns)
	local heads = CreateFrame("Frame", nil, page.frame)
	heads:SetHeight(16)
	heads:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, page.y)
	heads:SetPoint("RIGHT", page.frame, "RIGHT")
	for _, column in ipairs(columns) do
		local head = heads:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		head:SetTextColor(Theme.TIME:GetRGB())
		head:SetText(column[1])
		head:SetPoint(column[3] or "BOTTOM", heads, "BOTTOMLEFT", column[2], 0)
	end
	page.y = page.y - 16
end

-- A control's tooltip as the options' are (the name in white over its
-- sentence), with its row lit; `text` may be a function returning it.
local function ControlTip(row, control, title, text)
	control:HookScript("OnEnter", function()
		row.hover:Show()
		ns.Links.ShowTip(control, "ANCHOR_RIGHT", {
			{ title, HIGHLIGHT_FONT_COLOR },
			{ type(text) == "function" and text() or text, NORMAL_FONT_COLOR, true },
		}, control:GetObjectType() == "CheckButton" and 0 or -10, 0)
	end)
	control:HookScript("OnLeave", function()
		row.hover:Hide()
		HideTip(control)
	end)
end

-- A label's row on the channels page: its name; the box of its icon, where
-- it has one, with the icon as the chat draws it (ticked, the icon shows and
-- the name isn't used); a field for a name of its own, the game's in grey
-- while it's empty; the swatch of its color, which opens the game's color
-- picker; and the game's undo arrow while the row differs from the game's,
-- which puts all three back. `row.Set` takes what it stands for: `key`
-- (where its own name is kept), `kind` (its icon's, if any), `chatType` (its
-- color's), `label` and `default` (the game's name, in the field while
-- empty).
local function CreateLabelRow(page)
	local row = NewRow(page.frame)
	row.name = Label(row, "")

	local box = CreateBox(row)
	box:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)

	local field = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	field:SetSize(NAME_WIDTH, NAME_HEIGHT)
	field:SetPoint("LEFT", row, "LEFT", NAME_X, 0)
	field:SetAutoFocus(false)
	field:SetMaxLetters(ns.Channels.NAME_LETTERS)
	field:SetFontObject(GameFontHighlight)
	-- The game's name, as the game's own input boxes show what they're for:
	-- while the field is empty, focused or not.
	local hint = field:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	hint:SetPoint("LEFT")
	hint:SetPoint("RIGHT")
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(false)
	local function ShowHint()
		hint:SetShown(field:GetText() == "")
	end
	local function Stored()
		return row.spec and ns.Channels.OwnName(row.spec.key) or ""
	end

	local reset = CreateFrame("Button", nil, row)
	reset:SetSize(RESET_SIZE, RESET_SIZE)
	reset:SetPoint("LEFT", row, "LEFT", RESET_X, 0)
	reset:SetNormalAtlas(RESET_ATLAS)
	reset:SetHighlightAtlas(RESET_ATLAS, "ADD")
	reset:GetHighlightTexture():SetAlpha(RESET_GLOW)
	local function UpdateReset()
		local spec = row.spec
		reset:SetShown(spec ~= nil and not ns.Channels.IsDefault(spec.key, spec.kind, spec.chatType))
	end

	-- While typing, the chat shows the name as it is a moment after the last
	-- key (only that label's lines are composed again); Enter or leaving the
	-- field keeps it, with the game's option sound (a name set, or cleared
	-- back to the game's), and Esc puts back the one it had.
	local before, previewTimer
	local function Preview()
		if previewTimer then
			previewTimer:Cancel()
			previewTimer = nil
		end
		if row.spec then
			ns.Channels.SetOwnName(row.spec.key, field:GetText())
		end
	end
	-- Plain text only: the game's text codes start with "|", and the label
	-- puts the brackets around the name itself.
	field:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			local text = self:GetText()
			local clean = text:gsub("[|%[%]]", "")
			if clean ~= text then
				self:SetText(clean)
			end
			if previewTimer then
				previewTimer:Cancel()
			end
			previewTimer = C_Timer.NewTimer(PREVIEW_DELAY, Preview)
		end
		ShowHint()
	end)
	field:SetScript("OnEditFocusGained", function()
		before = Stored()
	end)
	field:SetScript("OnEditFocusLost", function(self)
		Preview()
		local after = Stored()
		self:SetText(after)
		if before and after ~= before then
			Theme.PlayCheck(after ~= "")
			UpdateReset()
			-- A channel left keeps its row only while it has a name.
			QueueRefresh()
		end
		before = nil
	end)
	field:SetScript("OnEnterPressed", field.ClearFocus)
	field:SetScript("OnEscapePressed", function(self)
		self:SetText(before or Stored())
		self:ClearFocus()
	end)

	local swatch = CreateFrame("Button", nil, row, "ColorSwatchTemplate")
	swatch:SetPoint("LEFT", row, "LEFT", COLOR_X, 0)
	swatch:SetScript("OnClick", function()
		local chatType = row.spec and row.spec.chatType
		local r, g, b = ns.Channels.ColorOf(chatType or "")
		if not r then
			return
		end
		local function Apply(newR, newG, newB)
			ns.Channels.SetColor(chatType, newR, newG, newB)
			swatch:SetColorRGB(newR, newG, newB)
			if row.icon then
				row.icon.Paint()
			end
			UpdateReset()
		end
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b,
			swatchFunc = function()
				Apply(ColorPickerFrame:GetColorRGB())
			end,
			cancelFunc = function()
				Apply(ColorPickerFrame:GetPreviousValues())
			end,
		})
	end)

	function row.Set(spec)
		-- The channels changed under a name being typed: it's kept for its own
		-- channel before the row shows another.
		if field:HasFocus() and row.spec and row.spec.key ~= spec.key then
			field:ClearFocus()
		end
		row.spec = spec
		row.name:SetText(spec.label)
		row.labelText = spec.label
		local iconShown = spec.kind ~= nil and ns.Channels.ShowsIcon(spec.kind)
		box:SetShown(spec.kind ~= nil)
		box:SetChecked(iconShown)
		if row.icon then
			row.icon.Paint()
		end
		hint:SetText(spec.default)
		if not field:HasFocus() then
			field:SetText(Stored())
		end
		-- Off while the icon shows: grey text in a faded, colorless box.
		field:SetEnabled(not iconShown)
		field:SetTextColor((iconShown and GRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR):GetRGB())
		field:SetAlpha(iconShown and NAME_OFF_ALPHA or 1)
		for _, part in ipairs({ field.Left, field.Middle, field.Right }) do
			part:SetDesaturated(iconShown)
		end
		ShowHint()
		local r, g, b = ns.Channels.ColorOf(spec.chatType or "")
		swatch:SetShown(r ~= nil)
		if r then
			swatch:SetColorRGB(r, g, b)
		end
		UpdateReset()
	end

	box:SetScript("OnClick", function(self)
		local on = self:GetChecked() and true or false
		Theme.PlayCheck(on)
		ns.Channels.SetShowsIcon(row.spec.kind, on)
		row.Set(row.spec)
	end)
	-- What was being typed goes too (the field puts back its name, silently).
	reset:SetScript("OnClick", function()
		if field:HasFocus() then
			field:SetText(before or Stored())
			field:ClearFocus()
		end
		Theme.PlayCheck(false)
		local spec = row.spec
		ns.Channels.ResetLabel(spec.key, spec.kind, spec.chatType)
		row.Set(spec)
		QueueRefresh()
	end)
	local function NameTip()
		return L.channelsNameTip:format("[" .. (row.spec and row.spec.default or "") .. "]")
	end
	row.hit:SetScript("OnClick", function()
		if field:IsEnabled() then
			field:SetFocus()
		end
	end)
	Hover(row, NameTip)
	ControlTip(row, box, L.channelsIconHead, function()
		local kind = row.spec and row.spec.kind
		return kind == "GUILD" and L.channelsCrestTip or kind == "RAID_WARNING" and L.channelsWarningTip or L.channelsIconTip
	end)
	ControlTip(row, field, NAME or L.channelsNameHead, NameTip)
	ControlTip(row, swatch, COLOR or L.channelsColorHead, L.channelsColorTip)
	ControlTip(row, reset, L.channelsResetHead, function()
		local spec = row.spec or {}
		if spec.kind and ns.Channels.HasIcon(spec.kind) then
			return L.channelsResetTip
		end
		return spec.chatType and L.channelsResetNameTip or L.channelsResetOnlyNameTip
	end)
	row.box, row.field = box, field
	return row
end

-- The guild's, the officers' and the groups' labels, one row each.
local function KindLabels(page)
	Heads(page, {
		{ L.channelsIconHead, CONTROL_X + 15 },
		{ NAME or L.channelsNameHead, NAME_X, "BOTTOMLEFT" },
		{ COLOR or L.channelsColorHead, COLOR_X + 8 },
	})
	for _, kind in ipairs(ns.Channels.LABEL_KINDS) do
		local label = ns.Channels.GroupLabel(kind)
		if label then
			local name = label:sub(2, -2)
			local row = CreateLabelRow(page)
			row:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, page.y)
			page.y = page.y - ROW
			local spec = { key = kind, chatType = kind, label = name, default = name }
			if ns.Channels.HasIcon(kind) then
				spec.kind = kind
				row.icon = ns.Channels.CreateLabelIcon(row, kind, LABEL_ICON)
				row.icon:SetPoint("LEFT", row.box, "RIGHT", 2, 0)
			end
			table.insert(page.refreshers, function()
				row.Set(spec)
			end)
		end
	end
end

-- The numbered channels the character is in, by number, then the ones it
-- left that kept a name of their own (so it can be changed or cleared).
-- Last on its page: the rows follow the channels, live while it's open.
local function NumberedLabels(page)
	Heads(page, {
		{ NAME or L.channelsNameHead, NAME_X, "BOTTOMLEFT" },
		{ COLOR or L.channelsColorHead, COLOR_X + 8 },
	})
	local top = page.y
	local rows = {}
	table.insert(page.refreshers, function()
		local specs, listed = {}, {}
		local list = { GetChannelList() }
		for index = 1, #list, 3 do
			local id, name = list[index], list[index + 1]
			if type(id) == "number" and type(name) == "string" then
				name = ns.Channels.BaseName(name)
				local key = ns.Channels.NameKey(name)
				listed[key] = true
				local label = id .. ". " .. name
				table.insert(specs, { key = key, chatType = "CHANNEL" .. id, label = label, default = label })
			end
		end
		local left = {}
		for key in pairs(ns.db.channelNames or {}) do
			local name = key:match("^channel:(.+)$")
			if name and not listed[key] then
				table.insert(left, name)
			end
		end
		table.sort(left)
		for _, name in ipairs(left) do
			table.insert(specs, { key = ns.Channels.NameKey(name), label = name, default = name })
		end
		for index, spec in ipairs(specs) do
			local row = rows[index] or CreateLabelRow(page)
			rows[index] = row
			row:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, top - (index - 1) * ROW)
			row.Set(spec)
			row:Show()
		end
		for index = #specs + 1, #rows do
			rows[index]:Hide()
		end
		page.extra = #specs * ROW
	end)
end

-- The game's chat font sizes and its words for them ("14 puntos", "14 pt":
-- its tab menu's FONT_SIZE_TEMPLATE), so the table and that menu show one
-- value alike. The number is the font's height in interface units, not
-- screen pixels (14 draws 16.8px on a 1440p screen at a 0.64 scale), so "px"
-- would be wrong (2026-10-13, the user asked which).
local FONT_SIZES = CHAT_FONT_HEIGHTS or { 12, 14, 16, 18, 20, 24, 27 }
local SIZE_FORMAT = FONT_SIZE_TEMPLATE or "%d pt"

local function SizeText(size)
	return SIZE_FORMAT:format(size)
end

local SIZE_CHOICES = {}
for _, size in ipairs(FONT_SIZES) do
	table.insert(SIZE_CHOICES, { size, SizeText(size) })
end

-- As the game's tab menu reads it (the font's height, rounded).
local function WindowSize(chatFrame)
	return math.floor(ns.Fonts.GetSize(chatFrame) + 0.5)
end

-- As the game's tab menu sets it; Fonts.lua follows FCF_SetChatWindowFontSize
-- to put Everchat's font back at the new size, and tells the open window.
local function SetWindowSize(chatFrame, size)
	if chatFrame and WindowSize(chatFrame) ~= size then
		FCF_SetChatWindowFontSize(nil, chatFrame, size)
	end
end

-- The font size of every tab at once, the game's own setting, set the way
-- its tab menu sets it, so both always agree; "Varios" while the tabs
-- differ. Each tab keeps its own size in its right-click menu, where the
-- game has it. Follows the tabs there are while the window is open, the
-- combat log among them.
local function SizeChoice(page)
	-- The windows, listed before the row reads them.
	local windows = {}
	table.insert(page.refreshers, function()
		windows = ListWindows(true)
	end)
	-- The size every tab has, if they share one.
	local function SharedSize()
		local shared
		for _, entry in ipairs(windows) do
			local size = WindowSize(entry.chatFrame)
			if shared and size ~= shared then
				return nil
			end
			shared = size
		end
		return shared
	end
	local dropdown = Dropdown(page, FONT_SIZE or L.fontSize, L.fontSizeTip, SIZE_CHOICES, SharedSize, function(size)
		for _, entry in ipairs(windows) do
			SetWindowSize(entry.chatFrame, size)
		end
	end)
	table.insert(page.refreshers, function()
		local shared = SharedSize()
		dropdown:SetDefaultText(shared and SizeText(shared) or L.sizeMixed)
	end)
end

-- The pages and what they hold.
local function BuildPages()
	-- How the chat looks (2026-10-13, the user's call; until then on the
	-- Messages page, and the font size only in each tab's menu). The game's
	-- word for the page.
	local appearance = NewPage(APPEARANCE_LABEL or L.optionsAppearance)
	-- Its size row follows the tabs and their sizes while the window is open.
	appearance.live = true
	-- The chat's look, live (Theme.lua); the arrows step through the themes.
	Section(appearance, L.optionsWindow)
	local themes = {}
	for _, key in ipairs(Theme.THEMES) do
		local name = key:sub(1, 1):upper() .. key:sub(2)
		table.insert(themes, { key, L["theme" .. name], L["theme" .. name .. "Tip"] })
	end
	Choice(appearance, "theme", L.optionTheme, L.optionThemeTip, themes, function(key)
		Theme.Set(key, Get("themeMinimal"))
	end)
	Check(appearance, "themeMinimal", L.optionMinimal, L.optionMinimalTip, function(minimal)
		Theme.Set(Get("theme"), minimal)
	end)
	-- How long new messages show while it's hidden, in the game's words ("10
	-- Seconds"): greyed in the other states, keeping its choice.
	local seconds = {}
	for _, value in ipairs({ 5, 10, 15, 30, 60 }) do
		table.insert(seconds, { value, (D_SECONDS or "%d s"):format(value) })
	end
	Choice(appearance, "chatRest", L.optionRest, L.optionRestTip, ns.Skin.RestChoices(), ns.Skin.SetRestMode)
	local _, secondsControl = Choice(appearance, "hideAtRestSeconds", L.optionRestSeconds, L.optionRestSecondsTip,
		seconds, ns.Skin.SetHiddenSeconds)
	table.insert(appearance.refreshers, function()
		secondsControl:SetEnabled(Get("chatRest") == "hidden")
	end)
	Check(appearance, "lockChat", L.optionLockChat, L.optionLockChatTip, ns.Resize.SetLocked)
	Section(appearance, L.optionsText)
	FontChoice(appearance)
	SizeChoice(appearance)
	Choice(appearance, "fontOutline", L.optionOutline, L.optionOutlineTip, {
		{ "none", L.outlineNone },
		{ "thin", L.outlineThin },
		{ "thick", L.outlineThick },
	}, ns.Fonts.Refresh)
	Choice(appearance, "lineSpacing", L.optionLineSpacing, L.optionLineSpacingTip, {
		{ "compact", L.spacingCompact },
		{ "normal", L.spacingNormal },
		{ "wide", L.spacingWide },
	}, ns.Timestamps.ApplySpacing)
	Check(appearance, "timestamps", L.optionTimestamps, L.optionTimestampsTip, function()
		ns.Timestamps.Refresh()
		if ns.db.timestamps and ns.Timestamps.GameShowsTimes() then
			ns.Print(L.timestampsGameOn)
		end
	end)
	-- The tooltip names the game's own setting for the guild's notices, in
	-- its words (Options > Social > Guild Member Alert).
	Check(appearance, "muteNotices", L.optionMuteNotices, L.optionMuteNoticesTip:format(GAMEMENU_OPTIONS or "Options",
		SOCIAL_LABEL or "Social", GUILDMEMBER_ALERT or "Guild Member Alert"), ns.Lines.Refresh)
	-- Changes show on the lines already in the chat too (Lines.lua). The
	-- labels' icons are on the channels page, in each label's row.
	Section(appearance, L.optionsIcons)
	Check(appearance, "socialMarks", L.optionSocialMarks, L.optionSocialMarksTip, ns.Lines.Refresh)
	-- Two switches, not one dropdown: the race and the class are independent
	-- (the game's settings use checkboxes for yes or no and dropdowns to pick
	-- one of several), and each row says what it does at a glance.
	Check(appearance, "raceMarks", L.optionRaceMarks, L.optionRaceMarksTip, ns.Lines.Refresh)
	Check(appearance, "classMarks", L.optionClassMarks, L.optionClassMarksTip, ns.Lines.Refresh)
	Check(appearance, "itemIcons", L.optionItemIcons, L.optionItemIconsTip, ns.Lines.Refresh)

	-- What the lines say and do.
	local messages = NewPage(L.optionsMessages)
	Section(messages, L.optionsLabels)
	Choice(messages, "surnames", L.optionSurnames, L.optionSurnamesTip, {
		{ "full", L.surnameFull, L.surnameFullTip },
		{ "initial", L.surnameInitial, L.surnameInitialTip },
		{ "hidden", L.surnameHidden, L.surnameHiddenTip },
	}, ns.Lines.Refresh)
	Check(messages, "localNames", L.optionLocalNames, L.optionLocalNamesTip, ns.Lines.Refresh)
	Check(messages, "inviteLinks", L.optionInviteLinks, L.optionInviteLinksTip, ns.Lines.Refresh)
	Section(messages, FILTERS or L.optionsFilters)
	Check(messages, "hideRepeats", L.optionHideRepeats, L.optionHideRepeatsTip)
	-- The languages shown in public talk (Filters.lua), as the game's own
	-- language filter lists them (its Group Finder: a "Languages" group, a box
	-- per language by the game's name for it, ticked = shown), and as the
	-- guidelines on groups of boxes ask (Windows UX: a noun for the group, the
	-- group's words not repeated in each box; affirmative labels): a dropdown
	-- "Hide messages in: None" said nothing until opened, and three boxes
	-- "Hide messages in Chinese / Korean / Cyrillic" repeated themselves
	-- (2026-10-13, the user). The grey line says once what a box does.
	Section(messages, L.optionsLanguages)
	Hint(messages, L.languagesHint)
	for _, key in ipairs(ns.Filters.Offered()) do
		Check(messages, ns.Filters.Option(key), ns.Filters.Name(key), L["languageTip_" .. key], ns.Filters.Changed, nil, true)
	end

	-- Each label's icon, own name and color: the guild's, the officers' and
	-- the groups', then the numbered channels'. The grey lines say once what
	-- empty means and what a ticked icon does; each control's tooltip again.
	local channels = NewPage(CHANNELS or L.optionsChannels)
	-- Its channels and colors follow the game's while the window is open.
	channels.live = true
	Section(channels, L.optionsChannelsKinds)
	Hint(channels, L.channelsKindsHint)
	KindLabels(channels)
	Section(channels, L.optionsChannelsNumbered)
	Hint(channels, L.channelsNumberedHint)
	Check(channels, "shortChannels", L.optionShortChannels, L.optionShortChannelsTip, ns.Lines.Refresh)
	NumberedLabels(channels)

	local alerts = NewPage(L.optionsAlerts)
	-- Its tabs table follows the tabs while the window is open.
	alerts.live = true
	Section(alerts, L.optionsMentions)
	Check(alerts, "mentions", L.optionMentions, L.optionMentionsTip, ns.Lines.Refresh)
	Check(alerts, "mentionAlts", L.optionMentionAlts, L.optionMentionAltsTip, function()
		ns.Alerts.ResetMentions()
		ns.Lines.Refresh()
	end)
	Check(alerts, "mentionSound", L.optionMentionSound, L.optionMentionSoundTip)
	Section(alerts, L.optionsQuiet)
	-- The same switch as the rail's bell; each shows the other's change.
	Check(alerts, "soundsMuted", L.optionMute, L.optionMuteTip, ns.Alerts.SetMuted)
	Check(alerts, "quietInCombat", L.optionQuiet, L.optionQuietTip)
	Section(alerts, L.optionsTabs)
	TabsTable(alerts)

	-- Each rail button by its own name and picture, as the taskbar settings of
	-- an operating system list theirs ("Button: ..." on every row was noise
	-- under a section that already says where they are).
	local rail = NewPage(L.optionsRailTab)
	Section(rail, L.optionsRail)
	for _, spec in ipairs(ns.Buttons.RAIL_BUTTONS) do
		Check(rail, spec.key, L[spec.label], L[spec.tip], ns.Buttons.Refresh, spec.icon)
	end

	local saved = NewPage(L.optionsHistoryTabs)
	Section(saved, L.optionsHistory)
	Check(saved, "keepHistory", L.optionHistory, L.optionHistoryTip, function(value)
		if not value then
			ns.History.Clear()
		end
	end)
	Action(saved, L.optionHistoryClear, L.optionHistoryClearButton, function()
		ns.History.Clear()
		ns.Print(L.historyCleared)
	end, L.optionHistoryClearTip)
	-- Its box follows the combat log tab's menu, which hides it too.
	saved.live = true
	Section(saved, L.optionsLayout)
	Check(saved, "hideCombatLogTab", L.optionCombatLogTab, L.optionCombatLogTabTip, ns.Header.SetCombatLogHidden,
		nil, true)
	Action(saved, L.optionTabCopy, L.optionTabCopyButton, ns.TabCopy.Open, L.optionTabCopyTip, true)
	-- Edit Mode only puts its layout back on a reload (calling it from here
	-- would taint it), so the button says so and reloads.
	Action(saved, L.optionLayoutReset, L.optionLayoutResetButton, function()
		ns.Resize.Forget()
		ReloadUI()
	end, L.optionLayoutResetTip)
end

-- The window keeps the game's gold whatever the chat's theme (Theme.GAME).
local function UpdatePageTab(tab)
	local look = Theme.GAME
	local color = tab.selected and look.TAB_OPEN or tab.hovered and look.TAB_TEXT_HOVER or look.TAB_TEXT
	tab.label:SetTextColor(color:GetRGB())
end

-- Shows a page: the stored values back on its rows, the window's height to
-- fit it.
local function ShowPage(index)
	current = index
	for i, page in ipairs(pages) do
		page.frame:SetShown(i == index)
		local tab = pageTabs[i]
		tab.selected = i == index
		tab.look:SetSelected(tab.selected)
		UpdatePageTab(tab)
	end
	if tabLine then
		local tab = pageTabs[index]
		local gap = ns.Tabs.OpenGap(tab.x, tab.x + tab:GetWidth(), PixelUtil.ConvertPixelsToUIForRegion(1, tab))
		tabLine:SetGap(gap.lineLeft, gap.lineRight, gap.softLeft, gap.softRight)
	end
	local page = pages[index]
	page.extra = 0
	for _, refresh in ipairs(page.refreshers) do
		refresh()
	end
	-- Pages differ in height; the window keeps its top where it is and grows
	-- or shrinks downward (centered, the tabs moved under the mouse).
	local left, top = window:GetLeft(), window:GetTop()
	if left and top then
		-- On whole pixels, so what's drawn at its pixel size stays sharp.
		local px = PixelUtil.ConvertPixelsToUIForRegion(1, window)
		window:ClearAllPoints()
		window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
			math.floor(left / px + 0.5) * px, math.floor(top / px + 0.5) * px)
	end
	window:SetHeight(TOP + PAD_TOP - page.y + page.extra + PAD_BOTTOM)
end

-- The page tabs, like the chat's: text only, the open one in its frame.
local function CreatePageTab(index, text, x)
	local tab = CreateFrame("Button", nil, window)
	tab:SetHeight(TAB_ROW)
	-- In the game's panel font like the rest of the window (in the chat tabs'
	-- Roboto the header read as another chat window's).
	tab.label = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	tab.label:SetText(text)
	tab.label:SetPoint("CENTER")
	tab:SetWidth(math.floor(tab.label:GetUnboundedStringWidth() + 2 * TAB_PADDING + 0.5))
	tab:SetPoint("BOTTOMLEFT", window, "TOPLEFT", TABS_X + x, -TOP)
	tab.x = TABS_X + x
	tab.look = ns.Tabs.CreateLook(tab, TAB_ROW)
	tab:SetScript("OnClick", function()
		if index ~= current then
			Theme.PlaySound("tab")
		end
		ShowPage(index)
	end)
	tab:SetScript("OnEnter", function(self)
		self.hovered = true
		self.look:SetHovered(true)
		UpdatePageTab(self)
	end)
	tab:SetScript("OnLeave", function(self)
		self.hovered = false
		self.look:SetHovered(false)
		UpdatePageTab(self)
	end)
	pageTabs[index] = tab
	return tab
end

-- Esc closes it, the way a game window closes: the window hears the keys
-- but lets every other one through. Letting keys through is restricted in
-- combat, so it's only set up and used out of combat; in combat Esc keeps
-- doing what it always does (the window stays until its close button).
local function ArmKeyboard()
	if keyboardArmed or InCombatLockdown() then
		return
	end
	window:EnableKeyboard(true)
	window:SetPropagateKeyboardInput(true)
	window:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then
			return
		end
		if key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			self:Hide()
			C_Timer.After(0, function()
				if not InCombatLockdown() then
					self:SetPropagateKeyboardInput(true)
				end
			end)
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)
	keyboardArmed = true
end

-- A window in Everchat's look: the options window and Everchat's dialogs
-- (copy the chat, a line or an address to copy, copy tabs, another chat
-- addon), so all of them speak alike. The card, as Baganator lays its window
-- out: a title bar in the header's color with the logo and the title
-- centered and the game's close button, the body under it; shadow and
-- hairline around it, all in the game's gold whatever the chat's theme. The
-- title bar moves it (the close button keeps its own clicks); it sounds as
-- it opens and closes. The body under the title bar, not behind it: two
-- fills on one layer would draw in no set order. The caller sizes and places
-- it and lays its content from `card.titleHeight` down; `card:SetTitle`.
local function CreateCard(width, title, strata, globalName)
	local card = CreateFrame("Frame", globalName, UIParent)
	card:SetFrameStrata(strata or "DIALOG")
	card:SetToplevel(true)
	card:SetWidth(width)
	card:SetClampedToScreen(true)
	card:EnableMouse(true)
	card:SetMovable(true)
	card:Hide()
	-- In whole screen pixels: at 1.2 pixels a unit, 54 units fell between
	-- pixel rows and the line under the options' page tabs sat a pixel above
	-- the open tab's sides.
	local unit = PixelUtil.ConvertPixelsToUIForRegion(1, card)
	local titleHeight = math.floor(TITLE_BAR / unit + 0.5) * unit
	card.titleHeight = titleHeight

	local titleBar = ns.Shapes.Fill(card, "BACKGROUND", 0, Theme.CARD_RADIUS, "TOP")
	titleBar:SetPoint("TOPLEFT", card, "TOPLEFT")
	titleBar:SetPoint("TOPRIGHT", card, "TOPRIGHT")
	titleBar:SetHeight(titleHeight)
	titleBar:SetColor(Theme.GAME.HEADER:GetRGBA())
	local body = ns.Shapes.Fill(card, "BACKGROUND", 0, Theme.CARD_RADIUS, "BOTTOM")
	body:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -titleHeight)
	body:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT")
	body:SetColor(Theme.BODY.r, Theme.BODY.g, Theme.BODY.b, WINDOW_ALPHA)
	local shadow = ns.Skin.CreateShadow(card, card, card, true, true)
	shadow:SetFrameStrata(card:GetFrameStrata())

	-- The game's own close button (its panels' red square with the gold X,
	-- Forever's member), tinted like the window's buttons, on whole screen
	-- pixels. The template without scripts: the click is ours.
	local close = CreateFrame("Button", nil, card, "UIPanelCloseButtonNoScripts")
	local closeSize = ns.Shapes.ArtPixels(close, CLOSE_PIXELS)
	close:SetSize(closeSize, closeSize)
	close:SetPoint("RIGHT", card, "TOPRIGHT", -4, -titleHeight / 2)
	close:SetFrameLevel(card:GetFrameLevel() + 5)
	-- Not fully desaturated like the big buttons: there the X turned beige and
	-- the button read dull; at 85% the red goes to a dark warm brown and the
	-- X keeps its gold.
	for _, texture in ipairs({ close:GetNormalTexture(), close:GetPushedTexture(), close:GetHighlightTexture(), close:GetDisabledTexture() }) do
		texture:SetDesaturation(CLOSE_DESATURATION)
		texture:SetVertexColor(unpack(BUTTON_TINT))
	end
	close:SetScript("OnClick", function()
		card:Hide()
	end)
	card.close = close

	-- The title in the game's gold, centered in the title bar with the logo
	-- before it. The logo made at its own size (Media/LogoSmall20 and 40, for
	-- dense screens) and drawn on whole pixels: the 64px art shrunk to 16
	-- looked soft.
	local name = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	name:SetWordWrap(false)
	local logo = card:CreateTexture(nil, "ARTWORK")
	local px = PixelUtil.ConvertPixelsToUIForRegion(1, logo)
	local artScale = math.max(1, math.ceil(1 / px - 0.5))
	logo:SetTexture(MEDIA .. (artScale >= 2 and "LogoSmall40" or "LogoSmall20"))
	local logoSize = LOGO_PIXELS * artScale * px
	logo:SetSize(logoSize, logoSize)
	local function Snap(units)
		return math.floor(units / px + 0.5) * px
	end
	-- Long titles stop short of the close button.
	local room = width - 2 * (closeSize + 8) - logoSize - 6
	function card.SetTitle(_, text)
		name:SetText(text)
		name:SetWidth(math.min(name:GetUnboundedStringWidth(), room))
		local groupWidth = logoSize + 6 + name:GetWidth()
		logo:ClearAllPoints()
		logo:SetPoint("TOPLEFT", card, "TOPLEFT", Snap((width - groupWidth) / 2), -Snap((titleHeight - logoSize) / 2))
		name:ClearAllPoints()
		name:SetPoint("LEFT", logo, "RIGHT", 6, 0)
	end
	card:SetTitle(title or "")

	local drag = CreateFrame("Frame", nil, card)
	drag:SetPoint("TOPLEFT", card, "TOPLEFT")
	drag:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", -(closeSize + 8), -titleHeight)
	drag:EnableMouse(true)
	drag:RegisterForDrag("LeftButton")
	drag:SetScript("OnDragStart", function()
		card:StartMoving()
	end)
	drag:SetScript("OnDragStop", function()
		card:StopMovingOrSizing()
	end)

	Theme.SoundOnShow(card)
	return card
end

Options.CreateWindow = CreateCard
Options.CreateTextButton = CreateTextButton

local function CreateWindow()
	window = CreateCard(WIDTH, L.optionsWindowTitle, "DIALOG", "EverchatOptionsWindow")
	window:SetHeight(300)
	window:SetPoint("TOP", UIParent, "TOP", 0, -UIParent:GetHeight() * 0.18)
	local unit = PixelUtil.ConvertPixelsToUIForRegion(1, window)
	TITLE_HEIGHT = window.titleHeight
	TOP = math.floor((TITLE_BAR + TAB_ROW) / unit + 0.5) * unit

	-- The page tabs on the body over the gold trim the open tab flows into.
	local tabRow = window:CreateTexture(nil, "BACKGROUND")
	-- Its bottom where the tabs stand (TOP), the line drawn on its last rows.
	tabRow:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -TITLE_HEIGHT)
	tabRow:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", 0, -TOP)
	tabRow:SetColorTexture(0, 0, 0, 0)
	tabLine = ns.Skin.CreateTrim(window, tabRow, "BOTTOM", true)

	BuildPages()
	local x = 0
	for index, page in ipairs(pages) do
		x = x + CreatePageTab(index, page.title, x):GetWidth()
	end

	window:HookScript("OnShow", ArmKeyboard)
	window:HookScript("OnHide", function()
		HideTip(window)
	end)
	window:RegisterEvent("PLAYER_REGEN_ENABLED")
	window:SetScript("OnEvent", function(self)
		if self:IsShown() then
			ArmKeyboard()
		end
	end)
end

function Options.Open()
	if not window then
		CreateWindow()
	end
	ShowPage(current)
	window:Show()
	window:Raise()
end

-- The rail's button, the slash command and the addon compartment.
function Options.Toggle()
	if window and window:IsShown() then
		window:Hide()
	else
		Options.Open()
	end
end

-- Everchat's page in the game's settings (Options > AddOns): a page of our
-- own (a canvas category, the settings' documented way for an addon's own
-- frame; it registers no settings, so nothing of ours reaches the settings
-- registry that action buttons read). The logo and name, the version, a
-- button that opens the window and the other ways to. (A list of the
-- window's pages and a fading gold line under the title read as generated;
-- the user had them out.)
local function CreateSettingsPage()
	local frame = CreateFrame("Frame")
	local group = CreateFrame("Frame", nil, frame)
	group:SetSize(460, 280)
	group:SetPoint("CENTER", frame, "CENTER", 0, 40)

	local logo = group:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(MEDIA .. "Logo")
	local size = ns.Shapes.ArtPixels(logo, 64)
	logo:SetSize(size, size)
	logo:SetPoint("TOP")

	local title = group:CreateFontString(nil, "ARTWORK", "SystemFont_Shadow_Huge4")
	title:SetTextColor(Theme.GOLD:GetRGB())
	title:SetText("Everchat")
	title:SetPoint("TOP", logo, "BOTTOM", 0, -8)

	local version = group:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	version:SetTextColor(Theme.TIME:GetRGB())
	version:SetText(L.optionsVersion:format(ns.version or ""))
	version:SetPoint("TOP", title, "BOTTOM", 0, -6)

	local open = CreateTextButton(group, L.optionsOpenButton, Options.Open, true, true)
	open:SetPoint("TOP", version, "BOTTOM", 0, -22)

	-- The other ways in, with a picture of the rail's options button where
	-- the sentence names it ("%s").
	local before, after = L.optionsPanelHint:match("^(.-)%%s(.*)$")
	local line = CreateFrame("Frame", nil, group)
	line:SetPoint("TOP", open, "BOTTOM", 0, -12)
	local function Part(text)
		local part = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		part:SetTextColor(Theme.TIME:GetRGB())
		part:SetText(text)
		return part
	end
	if before then
		local left, right = Part(before), Part(after)
		local picture = ns.Buttons.CreatePicture(line, "IconOptions")
		left:SetPoint("LEFT", line, "LEFT")
		picture:SetPoint("LEFT", left, "RIGHT", 4, 0)
		right:SetPoint("LEFT", picture, "RIGHT", 4, 0)
		line:SetSize(left:GetStringWidth() + picture:GetWidth() + right:GetStringWidth() + 8, picture:GetHeight())
	else
		local only = Part(L.optionsPanelHint)
		only:SetPoint("CENTER")
		line:SetSize(only:GetStringWidth(), only:GetStringHeight())
	end
	return frame
end

-- The open window follows what changes elsewhere: a tab's alerts switched in
-- its right-click menu (which stays open on its checkboxes) or on the rail,
-- and tabs made, closed, renamed, docked or moved (2026-10-12, the user: a
-- tab made with the window open only showed after reopening it). The other
-- way needs nothing: a menu reads them when it opens. At most one refresh a
-- frame, and none while the window is closed or on a page that doesn't show
-- them.
local refreshQueued = false

function QueueRefresh()
	if refreshQueued or not (window and window:IsShown() and pages[current].live) then
		return
	end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = false
		if window:IsShown() then
			ShowPage(current)
		end
	end)
end

function Options.Init()
	category = Settings.RegisterCanvasLayoutCategory(CreateSettingsPage(), "Everchat")
	Settings.RegisterAddOnCategory(category)
	ns.Alerts.OnSwitchChanged(QueueRefresh)
	ns.Header.OnTabsChanged(QueueRefresh)
	-- A tab's font size set in its right-click menu (or by the table's first
	-- row, once for all the tabs it changes).
	ns.Fonts.OnSizeChanged(QueueRefresh)
	-- Floating windows aren't the strip's: renamed or closed, they're told here.
	hooksecurefunc("FCF_SetWindowName", QueueRefresh)
	hooksecurefunc("FCF_Close", QueueRefresh)
	-- The channels page: channels joined or left, colors changed in the game's
	-- own chat settings, the guild's tabard. The color picker changes a color
	-- as its cursor moves: the page is drawn again once it closes (a row's own
	-- swatch keeps itself up to date meanwhile).
	local colorsChanged = false
	local events = CreateFrame("Frame")
	events:RegisterEvent("CHANNEL_UI_UPDATE")
	events:RegisterEvent("UPDATE_CHAT_COLOR")
	events:RegisterEvent("GUILDTABARD_UPDATE")
	events:SetScript("OnEvent", function(_, event)
		if event == "UPDATE_CHAT_COLOR" and ColorPickerFrame:IsShown() then
			colorsChanged = true
			return
		end
		QueueRefresh()
	end)
	ColorPickerFrame:HookScript("OnHide", function()
		if colorsChanged then
			colorsChanged = false
			QueueRefresh()
		end
	end)
end

-- The minimap's addon compartment entry (## AddonCompartmentFunc).
function Everchat_OpenOptions()
	Options.Toggle()
end
