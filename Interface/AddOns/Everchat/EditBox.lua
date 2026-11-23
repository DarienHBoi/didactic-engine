local _, ns = ...
local Theme = ns.Theme

local EditBox = {}
ns.EditBox = EditBox

-- Blizzard geometry (ChatFrameEditBox.xml, ChatFrameEditBox.lua): the edit box
-- is 32px tall and its text starts 15px in from its left edge and ends 13px
-- before its right one.
local TEXT_LEFT = 15
local TEXT_RIGHT = 13

-- The field inside the footer (Skin.CreateInset), the text 6px in. Its fill
-- is black at half, darker than the card and see-through like it (solid, it
-- was the heaviest piece of the chat), and fades with the chat's controls.
local FIELD_LEFT = 4
local FIELD_PADDING = 6
local FIELD_FILL = 0.5

local skinned = {}

-- Blizzard draws the edit box and its header in ChatFontNormal (14) whatever
-- the window's size; here they follow it, like the footer's hint.
local function ApplyFont(chatFrame, hint)
	local font = ns.Fonts.ForFrame(chatFrame)
	local editBox = chatFrame.editBox
	editBox:SetFontObject(font)
	-- The font object's centered justification would come along.
	editBox:SetJustifyH("LEFT")
	for _, region in ipairs({ editBox.header, editBox.headerSuffix, editBox.languageHeader }) do
		region:SetFontObject(font)
	end
	hint:SetFontObject(font)
end

local function CreateField(chatFrame, skin)
	local field = ns.Skin.CreateInset(chatFrame, "BORDER", "ARTWORK")
	field.fill:SetColor(0, 0, 0, FIELD_FILL)
	field.box:SetPoint("LEFT", skin.footer, "LEFT", FIELD_LEFT, 0)
	field.box:SetPoint("RIGHT", skin.footer, "RIGHT", -ns.Resize.FOOTER_CONTROLS_WIDTH, 0)
	field.box:SetHeight(Theme.INSET_HEIGHT)
	table.insert(skin.chrome, field.fill)
	table.insert(skin.chrome, field.edge)
	return field
end

-- The game draws the edit box above other windows (its template's DIALOG
-- strata), so what is being typed stays in sight with a window over the
-- chat. The field around it is the card's, below those windows, so the text
-- and its "Say:" would float over the window without their box. While
-- typing, a copy of the field on the edit box's strata, just under the edit
-- box, takes the field's place: the whole box shows, as the game's own does.
local function CreateRaisedField(field)
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetAllPoints(field.box)
	frame:Hide()
	local raised = ns.Skin.CreateInset(frame, "BORDER", "ARTWORK")
	raised.fill:SetColor(0, 0, 0, FIELD_FILL)
	raised.box:SetAllPoints(field.box)
	raised.frame = frame
	return raised
end

function EditBox.Skin(chatFrame, skin)
	local editBox = chatFrame.editBox
	if not editBox or skinned[editBox] then
		return
	end

	local name = editBox:GetName()
	_G[name .. "Left"]:SetTexture(nil)
	_G[name .. "Right"]:SetTexture(nil)
	_G[name .. "Mid"]:SetTexture(nil)
	editBox.focusLeft:SetTexture(nil)
	editBox.focusMid:SetTexture(nil)
	editBox.focusRight:SetTexture(nil)

	local field = CreateField(chatFrame, skin)
	local raised = CreateRaisedField(field)

	-- The edit box spans the field, its text FIELD_PADDING in from each side.
	-- Only anchored in FloatingChatFrame.xml; Blizzard never moves it afterwards.
	editBox:ClearAllPoints()
	editBox:SetPoint("LEFT", field.box, "LEFT", FIELD_PADDING - TEXT_LEFT, 0)
	editBox:SetPoint("RIGHT", field.box, "RIGHT", TEXT_RIGHT - FIELD_PADDING, 0)

	-- Where the text will start, while the edit box is hidden.
	local hint = chatFrame:CreateFontString(nil, "ARTWORK")
	hint:SetFontObject(ns.Fonts.ForFrame(chatFrame))
	hint:SetTextColor(Theme.TIME:GetRGB())
	hint:SetText(ns.L.typeHint)
	hint:SetPoint("LEFT", field.box, "LEFT", FIELD_PADDING, 0)
	skin.hint = hint
	-- It rests with the field (Skin.lua's fade).
	table.insert(skin.chrome, hint)
	ApplyFont(chatFrame, hint)
	ns.Fonts.OnSizeChanged(function(changed)
		if changed == chatFrame then
			ApplyFont(chatFrame, hint)
		end
	end)

	-- While the player types, the field's edge takes the chat type's color
	-- (Blizzard's UpdateHeader gives the edit box's text that color on every
	-- type change), the whole chat lights up and the hint hides. Read from the
	-- edit box each frame by a frame of our own: under Forever's addon
	-- restrictions (instances, combat), Blizzard's own calls to an edit box
	-- method an addon hooked fail ("attempt to call a nil value"), which is how
	-- hooks on SetFocusRegionsShown/SetFocusRegionVertexColors broke opening
	-- the chat in a dungeon.
	-- The watcher is the edit box's child, so it only ticks while the box is
	-- shown (one per window; parented to UIParent they all ticked, every
	-- frame), and it reads the color only while typing.
	local typing, r, g, b = false, nil, nil, nil
	local function SetEdgeColor(...)
		field:SetEdgeColor(...)
		raised:SetEdgeColor(...)
	end
	-- Nobody typing: the theme's edge, as much as the style shows of it.
	local function RestEdge()
		local edge = Theme.FIELD_EDGE
		SetEdgeColor(edge.r, edge.g, edge.b, edge.a * Theme.FIELD_EDGE_REST)
	end
	local function SetTyping(focused)
		typing = focused
		ns.Skin.SetTyping(skin, focused)
		raised.frame:SetShown(focused)
		field.fill:SetShown(not focused)
		field.edge:SetShown(not focused)
		if not focused then
			r, g, b = nil, nil, nil
			RestEdge()
		end
	end
	-- Kept just under the edit box, which rises as it takes the focus.
	local function PlaceRaised()
		local strata, level = editBox:GetFrameStrata(), math.max(editBox:GetFrameLevel() - 1, 0)
		local frame = raised.frame
		if frame:GetFrameStrata() ~= strata or frame:GetFrameLevel() ~= level then
			frame:SetFrameStrata(strata)
			frame:SetFrameLevel(level)
		end
	end
	-- The header ("[1. General: Elwynn Forest]: ", "Guild: ") under the name
	-- the lines show (Channels.HeaderText), laid out as UpdateHeader lays out
	-- the game's: half the box at most, the text after it. Read and written
	-- from the watcher, like the color; `shownHeader` is the header last seen
	-- or written, so a new one from the game is caught in the frame it comes.
	local header, headerSuffix, languageHeader = editBox.header, editBox.headerSuffix, editBox.languageHeader
	local shownHeader
	local function NameHeader()
		local current = header:GetText()
		if current == shownHeader or not canaccessvalue(current) then
			return
		end
		shownHeader = current
		local chatType = editBox:GetAttribute("chatType")
		local number, channelName
		if chatType == "CHANNEL" then
			number, channelName = GetChannelName(editBox:GetAttribute("channelTarget"))
		end
		local text = ns.Channels.HeaderText(chatType, channelName, current, number)
		if not text then
			return
		end
		header:SetWidth(0)
		header:SetText(text)
		local half = editBox:GetWidth() / 2
		headerSuffix:SetShown(header:GetStringWidth() > half)
		if headerSuffix:IsShown() then
			header:SetWidth(half)
		end
		local languageWidth = languageHeader and languageHeader:IsShown() and languageHeader:GetWidth() or 0
		editBox:SetTextInsets(TEXT_LEFT + header:GetWidth() + (headerSuffix:IsShown() and headerSuffix:GetWidth() or 0)
			+ languageWidth, TEXT_RIGHT, 0, 0)
		shownHeader = text
	end
	-- The box types at its window's size (ApplyFont). Anything else that gives
	-- it another (another chat addon's input bar) is undone while typing, and
	-- /everchat font says what it was. Should putting it back not take, it's
	-- left alone rather than tried on every frame.
	local keepFont = true
	local function KeepFont()
		local _, height = editBox:GetFont()
		local _, expected = ns.Fonts.ForFrame(chatFrame):GetFont()
		if not (keepFont and height and expected and math.abs(height - expected) > 0.5) then
			return
		end
		ns.Fonts.NoteForeignFont(editBox)
		ApplyFont(chatFrame, hint)
		local _, now = editBox:GetFont()
		keepFont = now ~= nil and math.abs(now - expected) <= 0.5
	end
	local watcher = CreateFrame("Frame", nil, editBox)
	watcher:SetScript("OnUpdate", function()
		local focused = editBox:HasFocus()
		if not focused then
			if typing then
				SetTyping(false)
				shownHeader = nil
			end
			return
		end
		if not typing then
			SetTyping(true)
		end
		PlaceRaised()
		KeepFont()
		NameHeader()
		local nr, ng, nb = editBox:GetTextColor()
		if nr ~= r or ng ~= g or nb ~= b then
			r, g, b = nr, ng, nb
			SetEdgeColor(r, g, b, 1)
		end
	end)
	-- Hidden mid-typing (the window closed or undocked): back to rest.
	watcher:SetScript("OnHide", function()
		if typing then
			SetTyping(false)
		end
		shownHeader = nil
	end)
	-- A new theme: the resting edge in its color (while typing it's the
	-- chat type's).
	Theme.OnChanged(function()
		if not typing then
			RestEdge()
		end
	end)
	RestEdge()

	skinned[editBox] = true
end
