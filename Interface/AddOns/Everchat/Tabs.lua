local _, ns = ...
local Theme = ns.Theme

local Tabs = {}
ns.Tabs = Tabs


-- Blizzard's tab art; the header replaces it.
local TAB_ART = {
	"Left", "Middle", "Right",
	"ActiveLeft", "ActiveMiddle", "ActiveRight",
	"HighlightLeft", "HighlightMiddle", "HighlightRight",
}

-- Each tab owns its whole slice of the header. The active one is open into
-- the message area: its block runs from the header's color at its top to the
-- message area's at its bottom (the header's fill is open under it,
-- Skin.lua), so it melts into both at any opacity, framed by one line of the
-- theme's metal, light at the top and running down its sides into the
-- header's line, with a soft light under its top edge. In a theme without
-- metal (Theme.OPEN_TAB_MARK "line") only its name marks it, and the header's
-- line lit under it (Skin.lua). Tabs stand on the header's bottom edge, so
-- heights are measured up from the tab's bottom. The drag ghost and the
-- options window's page tabs stand on a fill that stays under them: their
-- blocks go from clear to the body's color.
local FILL_ALPHA = 0.95
local HOVER_ALPHA = 0.05
-- The frame's top, a little short of solid; its sides end in the line's own
-- color and strength (Theme.LINE, HEADER_LINE_ALPHA), so frame and line read
-- as one thread. Only the active tab has a frame: one around the whole chat
-- made it a separate box (the game's chat and other chat addons have none),
-- and three rings (a dark line around a light row and a deeper one) on a
-- near-opaque block weighed more than the chat around it.
local RIM_TOP_ALPHA = 0.9
-- The light under the frame's top edge: the metal's color, gone two fifths
-- of the way down.
local GLOW_ALPHA = 0.16
local GLOW_SHARE = 0.4
-- The frame's feet, in screen pixels: at the bottom each side curves out into
-- the header's line (Theme.TAB_FOOT), over the corner the curve leaves on the
-- tab's side, filled like the tab (Media/Notch, what a rounded corner leaves
-- out). The header's line opens around them (Tabs.OpenGap), its row inside
-- reaching SOFT_REACH pixels further, to the curve's inner side; the
-- header's fill reaches under the frame's sides, its runs' rounded corners
-- being the curves' other side.
local FOOT = Theme.TAB_FOOT
local SOFT_REACH = 1

-- Our state lives here, never as keys on Blizzard frames.
local tabParts = {}
-- The drag ghosts (Header.lua makes one).
local ghosts = {}

local function Framed()
	return Theme.OPEN_TAB_MARK == "frame"
end

-- The chat's font at the tab size (Fonts.lua). A tab is a button, which puts
-- its normal or highlight font object back on its label as the mouse comes
-- and goes, so those are set too.
local function SetLabelFont(text, tab)
	local font = ns.Fonts.ForTabs()
	if tab then
		tab:SetNormalFontObject(font)
		tab:SetHighlightFontObject(font)
		tab:SetDisabledFontObject(font)
	end
	text:SetFontObject(font)
end

-- The feet's curves (and a side's straight end at the card's edge), in the
-- line's color and strength as the frame fades.
local function PaintFeet(look)
	local line = look.palette.LINE
	for _, ring in ipairs(look.rings) do
		ring:SetVertexColor(line.r, line.g, line.b)
		ring:SetAlpha(look.rimAlpha * look.palette.HEADER_LINE_ALPHA * look.lineFactor)
	end
end

-- The frame's sides end in the line's strength, which also follows the
-- window's background opacity (Skin.lua, `lineFactor`), so the frame never
-- meets a fainter line.
local function PaintLook(look, palette)
	look.palette = palette
	local top, line = palette.RIM_TOP, palette.LINE
	look.rimTop:SetRGBA(top.r, top.g, top.b, RIM_TOP_ALPHA)
	look.rimBottom:SetRGBA(line.r, line.g, line.b, palette.HEADER_LINE_ALPHA * look.lineFactor)
	look.rim:SetVerticalGradient(look.rimTop, look.rimBottom)
	look.glowTop:SetRGBA(top.r, top.g, top.b, GLOW_ALPHA)
	look.glowBottom:SetRGBA(top.r, top.g, top.b, 0)
	look.glow:SetFillGradient(look.glowTop, look.glowBottom, look.glowHeight)
	PaintFeet(look)
end

-- The block between the frame's sides, or under the left one too while it
-- runs down the card's edge.
local function PlaceBlock(look)
	local px = look.px
	local inset = look.feet and px or 0
	look.place(look.block, -px, look.leftFoot and inset or 0, inset)
end

-- The active look on a tab, the drag ghost or a page tab: the block, the
-- frame and the light under its top. `place(shape, bottom, left, right)`
-- anchors a shape to the header-tall box (`height`, the chat's header by
-- default), its bottom at `bottom` and its sides `left` and `right` in, and
-- can place it again. The block reaches
-- through the header's line (its last two rows, Skin.lua) to a pixel below
-- the box, square: at its top it has the header's color, and the frame draws
-- the round corners (rounded, its corners outside the curve let the world
-- show through the header's opening). `palette` holds the metal's colors.
-- With `feet` the frame's sides stop above the line and curve out into it,
-- standing on the header's fill, which reaches under them, so the block
-- stops inside them; a left side at the card's edge (Tabs.SetLeftFoot) runs
-- straight down it instead, over the block. Without (the drag ghost, over
-- the line), the sides run down through the line.
local function AddLook(owner, place, px, palette, feet, height)
	height = height or Theme.HEADER_HEIGHT
	local look = {
		place = place,
		px = px,
		height = height,
		glowHeight = height * GLOW_SHARE,
		feet = feet,
		leftFoot = feet,
		block = ns.Shapes.Fill(owner, "BACKGROUND", 0, Theme.TAB_RADIUS, "NONE"),
		rim = place(ns.Shapes.Outline(owner, "BORDER", 1, Theme.TAB_RADIUS, "TOP", "BOTTOM"), feet and FOOT * px or -px),
		glow = ns.Shapes.Fill(owner, "BACKGROUND", 1, Theme.TAB_RADIUS - 1, "TOP"),
		rings = {},
		notches = {},
		left = {},
		rimAlpha = 1,
		lineFactor = 1,
		blockHeight = height + px,
		blockTop = CreateColor(0, 0, 0, 0),
		blockBottom = CreateColor(0, 0, 0, 0),
		rimTop = CreateColor(1, 1, 1, 1),
		rimBottom = CreateColor(1, 1, 1, 1),
		glowTop = CreateColor(1, 1, 1, 1),
		glowBottom = CreateColor(1, 1, 1, 0),
	}
	PlaceBlock(look)
	look.glow:SetPoint("TOPLEFT", look.rim.box, "TOPLEFT", px, -px)
	look.glow:SetPoint("TOPRIGHT", look.rim.box, "TOPRIGHT", -px, -px)
	look.glow:SetHeight(look.glowHeight)
	look.pieces = { look.block, look.rim, look.glow }
	if feet then
		-- Each foot's square stands on the header's bottom, its inner column
		-- the frame's side: a curve from the side down into the line's row
		-- (Ring) over the corner under it (Notch), mirrored for each side.
		local function Foot(point, anchor, x, pieces)
			local notch = ns.Shapes.Corner(owner, "BACKGROUND", 0, "Notch", FOOT, point)
			local ring = ns.Shapes.Corner(owner, "BORDER", 1, "Ring", FOOT, point)
			for _, piece in ipairs({ notch, ring }) do
				piece:SetPoint(point, look.rim.box, anchor, x, -FOOT * px)
				table.insert(pieces, piece)
			end
			table.insert(look.rings, ring)
			table.insert(look.notches, notch)
		end
		Foot("BOTTOMLEFT", "BOTTOMRIGHT", -px, look.pieces)
		Foot("BOTTOMRIGHT", "BOTTOMLEFT", px, look.left)
		-- The left side's straight end, down the card's edge.
		look.tail = owner:CreateTexture(nil, "BORDER", nil, 1)
		look.tail:SetColorTexture(1, 1, 1, 1)
		look.tail:SetPoint("TOPLEFT", look.rim.box, "BOTTOMLEFT")
		look.tail:SetSize(px, FOOT * px)
		table.insert(look.rings, look.tail)
	end
	PaintLook(look, palette)
	return look
end

-- Where the header's line and fill open around an open tab spanning `left`
-- to `right` along the header (units, `px` a screen pixel), shown up to
-- `limit` (Skin.lua and the options' page tabs). The line opens to where the
-- feet's curves meet it, its row inside to their inner side; the fill to
-- under the frame's sides, its runs' ends rounded beside a foot. A side has
-- no foot at the header's left end (it's the card's edge) or cut off at
-- `limit`. The same table every time.
local opening = {}

function Tabs.OpenGap(left, right, px, limit)
	local foot, reach = FOOT * px, SOFT_REACH * px
	opening.leftFoot = left > 0
	if opening.leftFoot then
		opening.lineLeft = left + px - foot
		opening.softLeft = opening.lineLeft + reach
		opening.fillLeft = left + px
	else
		opening.lineLeft, opening.softLeft, opening.fillLeft = left, left, left
	end
	opening.rightFoot = not limit or right < limit
	if opening.rightFoot then
		opening.lineRight = right - px + foot
		opening.softRight = opening.lineRight - reach
		opening.fillRight = right - px
	else
		opening.lineRight, opening.softRight, opening.fillRight = right, right, right
	end
	return opening
end

-- A look's block from (tr, tg, tb, ta) at its top to (br, bg, bb, ba) at its
-- bottom, and the feet's corners in its colors at their rows.
local footTop, footBottom = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)

local function BlockAt(look, height, color)
	local t = 1 - height / look.height
	local top, bottom = look.blockTop, look.blockBottom
	color:SetRGBA(Lerp(top.r, bottom.r, t), Lerp(top.g, bottom.g, t), Lerp(top.b, bottom.b, t), Lerp(top.a, bottom.a, t))
end

local function PaintBlock(look, tr, tg, tb, ta, br, bg, bb, ba)
	look.blockTop:SetRGBA(tr, tg, tb, ta)
	look.blockBottom:SetRGBA(br, bg, bb, ba)
	look.block:SetFillGradient(look.blockTop, look.blockBottom, look.blockHeight)
	if look.feet then
		BlockAt(look, FOOT * look.px, footTop)
		BlockAt(look, 0, footBottom)
		for _, notch in ipairs(look.notches) do
			ns.Shapes.SetGradient(notch, "VERTICAL", footBottom, footTop)
		end
	end
end

-- A name cut at the strip's end fades out over the strip's last stretch. A
-- font string can't fade part of its text (SetAlphaGradient flickered on the
-- tabs as the game redrew them), and letters drawn one by one never sat
-- where the whole name puts them (the game draws text a little off its
-- measure, and each letter landed on a pixel of its own, opening gaps), so
-- while it's cut the name is drawn again in thin slices of the tab: frames
-- of our own, each clipping a copy of the label laid out exactly as the
-- label is, at its share of the name's alpha. The game's label is hidden
-- meanwhile. A name that can't be read (a secret whisper name) is just cut.
local SLICE = 2
-- Room before the tab's edge in the first slice, for a letter's overhang.
local SLICE_MARGIN = 4

-- The label's text, unless it's secret.
local function ReadableName(parts)
	local name = parts.text:GetText()
	if name and canaccessvalue(name) then
		return name
	end
end

local function Slice(parts, index)
	parts.slices = parts.slices or {}
	local slice = parts.slices[index]
	if not slice then
		local clip = CreateFrame("Frame", nil, parts.tab)
		clip:SetClipsChildren(true)
		local copy = clip:CreateFontString(nil, (parts.text:GetDrawLayer()))
		copy:SetIgnoreParentAlpha(true)
		copy:SetAllPoints(parts.text)
		slice = { clip = clip, copy = copy, share = 1 }
		parts.slices[index] = slice
	end
	return slice
end

-- The copies' alpha (each its share of the name's), as the name's own alpha
-- changes with the chat's fade: on every step of it, so nothing else here.
local function PaintNameFade(parts)
	local alpha = parts.textAlpha or 1
	if not parts.faded then
		parts.text:SetAlpha(alpha)
		return
	end
	parts.text:SetAlpha(0)
	for index = 1, parts.faded do
		local slice = parts.slices[index]
		slice.copy:SetAlpha(alpha * slice.share)
	end
end

-- The copies' color, the name's own (Blizzard's for a whisper window).
local function ColorNameFade(parts)
	if parts.faded then
		local r, g, b = parts.text:GetTextColor()
		for index = 1, parts.faded do
			parts.slices[index].copy:SetTextColor(r, g, b)
		end
	end
end

-- The slices along the tab: the name whole up to where the fade starts, then
-- thin slices fading to nothing where the strip ends.
local function LayoutNameFade(parts)
	local fade = parts.fade
	local used = 0
	if fade and fade.name then
		local label, tab = parts.text, parts.tab
		local previous
		local function Add(left, width, share)
			used = used + 1
			local slice = Slice(parts, used)
			local clip, copy = slice.clip, slice.copy
			clip:ClearAllPoints()
			if previous then
				-- Each starts where the last ends: no column is drawn twice or
				-- left out.
				clip:SetPoint("TOPLEFT", previous, "TOPRIGHT")
				clip:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT")
			else
				clip:SetPoint("TOPLEFT", tab, "TOPLEFT", left, 0)
				clip:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", left, 0)
			end
			clip:SetWidth(width)
			clip:Show()
			if slice.name ~= fade.name or slice.font ~= fade.font then
				slice.name, slice.font = fade.name, fade.font
				copy:SetFontObject(fade.font)
				copy:SetJustifyH(label:GetJustifyH())
				copy:SetJustifyV(label:GetJustifyV())
				copy:SetWordWrap(label:CanWordWrap())
				copy:SetNonSpaceWrap(label:CanNonSpaceWrap())
				copy:SetText(fade.name)
			end
			slice.share = share
			previous = clip
		end
		if fade.from > -SLICE_MARGIN then
			Add(-SLICE_MARGIN, fade.from + SLICE_MARGIN, 1)
		end
		local count = math.max(1, math.ceil((fade.to - fade.from) / SLICE))
		local width = (fade.to - fade.from) / count
		for index = 1, count do
			Add(fade.from, width, 1 - (index - 0.5) / count)
		end
		parts.faded = used
	else
		parts.faded = nil
	end
	for index, slice in ipairs(parts.slices or {}) do
		if index > used then
			slice.clip:Hide()
		end
	end
	ColorNameFade(parts)
	PaintNameFade(parts)
end

-- Where the name fades, along the tab from its left edge (Header.lua), or
-- nil while it isn't cut.
function Tabs.SetNameFade(tab, from, to)
	local parts = tabParts[tab]
	if not parts then
		return
	end
	local fade = parts.fade
	if from == nil then
		if fade then
			parts.fade = nil
			LayoutNameFade(parts)
		end
		return
	end
	local name, font = ReadableName(parts), parts.text:GetFontObject() or ns.Fonts.ForTabs()
	if fade and fade.name == name and fade.font == font
		and math.abs(fade.from - from) < 0.25 and math.abs(fade.to - to) < 0.25 then
		return
	end
	parts.fade = { from = from, to = to, name = name, font = font }
	LayoutNameFade(parts)
end

local function UpdateTextColor(tab, parts)
	-- Keep Blizzard's custom tab colors (e.g. whisper windows).
	local custom = tab.selectedColorTable
	if custom then
		parts.text:SetTextColor(custom.r, custom.g, custom.b)
	elseif parts.selected then
		parts.text:SetTextColor(Theme.TAB_OPEN:GetRGB())
	else
		local rest, hover, fade = Theme.TAB_TEXT, Theme.TAB_TEXT_HOVER, parts.hoverFade
		parts.text:SetTextColor(Lerp(rest.r, hover.r, fade), Lerp(rest.g, hover.g, fade), Lerp(rest.b, hover.b, fade))
	end
	ColorNameFade(parts)
end

-- A tab under the mouse lights up over a moment, and goes back the same way
-- (the scroll bar widens as briefly): its name, and in a framed theme its
-- light block (without a frame its stretch of the header's line, Skin.lua).
-- `item.hoverFade` runs to `item.hoverTarget`; `item.paintHover()` shows it.
local HOVER_TIME = 0.12
local fading = {}
local fader = CreateFrame("Frame")

local function StepHovers(_, elapsed)
	local step = elapsed / HOVER_TIME
	for item in pairs(fading) do
		if item.hoverTarget > item.hoverFade then
			item.hoverFade = math.min(item.hoverTarget, item.hoverFade + step)
		else
			item.hoverFade = math.max(item.hoverTarget, item.hoverFade - step)
		end
		item.paintHover()
		if item.hoverFade == item.hoverTarget then
			fading[item] = nil
		end
	end
	if not next(fading) then
		fader:SetScript("OnUpdate", nil)
	end
end

local function FadeHover(item, target)
	item.hoverTarget = target
	if item.hoverFade == target then
		fading[item] = nil
		item.paintHover()
		return
	end
	fading[item] = true
	fader:SetScript("OnUpdate", StepHovers)
end

-- The chat's fade (Skin.lua): at rest the open tab's frame and name as the
-- game's open tab rests, the other names as its other tabs, or at full while
-- they have unread messages, as its alerting tabs. The light under the frame
-- goes. The open tab's block follows the fade in its colors
-- (Tabs.SetBlockColors): at rest the header and the message area look alike,
-- and so does the block, with no box left. `lineFactor`: how much of the
-- header's line the window's background opacity shows (kept when omitted).
function Tabs.ApplyAlpha(parts, lit, lineFactor)
	if not parts then
		return
	end
	parts.lit = lit
	local look = parts.look
	local open = Theme.Rest(Theme.REST_OPEN_TAB, lit)
	if lineFactor and lineFactor ~= look.lineFactor then
		look.lineFactor = lineFactor
		look.stale = true
	end
	look.rimAlpha = open
	-- Only the open tab shows its look; the others are painted when opened
	-- (UpdateSelection), not on every frame of the chat's fade.
	if parts.selected and Framed() then
		if look.stale then
			look.stale = nil
			PaintLook(look, look.palette)
		end
		look.rim:SetAlpha(open)
		PaintFeet(look)
		look.glow:SetAlpha(lit)
	end
	local rest = parts.alerting and Theme.REST_ALERT or Theme.REST_TAB
	parts.textAlpha = parts.selected and open or Theme.Rest(rest, lit)
	PaintNameFade(parts)
	-- The unread dot stays whole, save while the chat hides at rest.
	ns.Alerts.SetTabFade(parts.tab, Theme.Rest(1, lit))
end

-- Whether the tab has unread messages (Alerts.lua lights its dot).
function Tabs.SetAlerting(tab, alerting)
	local parts = tabParts[tab]
	if not parts or parts.alerting == alerting then
		return
	end
	parts.alerting = alerting
	Tabs.ApplyAlpha(parts, parts.lit)
end

-- The open tab's look, its left side curving into the header's line or
-- running down the card's edge (a floating window's tab is always at its
-- card's edge).
local function ShowLook(parts)
	local look = parts.look
	local leftFoot = parts.leftFoot and parts.chatFrame.isDocked or false
	if look.leftFoot ~= leftFoot then
		look.leftFoot = leftFoot
		PlaceBlock(look)
	end
	local shown = parts.selected and Framed()
	-- Its colors as the chat's fade last set them (Tabs.SetBlockColors).
	if shown and parts.blockColors then
		PaintBlock(look, unpack(parts.blockColors))
	end
	for _, region in ipairs(look.pieces) do
		region:SetShown(shown)
	end
	for _, region in ipairs(look.left) do
		region:SetShown(shown and leftFoot)
	end
	look.tail:SetShown(shown and not leftFoot)
end

function Tabs.UpdateSelection(tab, selected)
	local parts = tabParts[tab]
	if not parts then
		return
	end
	parts.selected = selected
	ShowLook(parts)
	-- A framed theme lightens the tab under the mouse; without a frame its
	-- stretch of the header's line lights up (Header.lua, Skin.lua). The open
	-- tab has neither.
	if selected then
		parts.hoverFade = 0
	end
	FadeHover(parts, (parts.hovered and not selected) and 1 or 0)
	ns.Header.SetHovered(tab, parts.hovered and not selected)
	Tabs.ApplyAlpha(parts, parts.lit)
end

-- Whether a docked tab's left side curves into the header's line, or runs
-- straight down the card's edge (the first tab, scrolled to the start;
-- Header.lua, for every docked tab as it's placed).
function Tabs.SetLeftFoot(tab, foot)
	local parts = tabParts[tab]
	if parts and parts.leftFoot ~= foot then
		parts.leftFoot = foot
		ShowLook(parts)
	end
end

-- Moves the label left by `shift` (0 puts it back). A tab with an unread dot
-- (Alerts.lua) centers its name and the dot together, so the dot isn't
-- squeezed against the next tab (it sat 4px from an active neighbour's edge);
-- the tab keeps its width, so nothing else moves.
function Tabs.SetLabelShift(tab, shift)
	local parts = tabParts[tab]
	if not parts or parts.shift == shift then
		return
	end
	parts.shift = shift
	local point, relativeTo, relativePoint, x, y = unpack(parts.anchor)
	parts.text:ClearAllPoints()
	parts.text:SetPoint(point, relativeTo, relativePoint, x - shift, y)
end

-- The open tab's block, from the header's look at its top to the message
-- area's at its bottom (Skin.lua, at every step of the chat's fade). Kept,
-- and painted while it shows.
function Tabs.SetBlockColors(parts, tr, tg, tb, ta, br, bg, bb, ba)
	if not (parts and parts.look) then
		return
	end
	local colors = parts.blockColors or {}
	colors[1], colors[2], colors[3], colors[4], colors[5], colors[6], colors[7], colors[8] = tr, tg, tb, ta, br, bg, bb, ba
	parts.blockColors = colors
	if parts.selected and Framed() then
		PaintBlock(parts.look, tr, tg, tb, ta, br, bg, bb, ba)
	end
end

-- The drag ghost's block in the body's color (Header.lua, the window it
-- stands for): clear at its top, over the header's own fill.
function Tabs.SetFillColor(parts, r, g, b)
	if parts and parts.look then
		PaintBlock(parts.look, r, g, b, 0, r, g, b, FILL_ALPHA)
	end
end

function Tabs.Skin(tab, chatFrame)
	for _, key in ipairs(TAB_ART) do
		tab[key]:SetTexture(nil)
	end
	-- Blizzard's own alert (a light along the tab's bottom it flashes for
	-- whispers) gives way to Everchat's dot (Alerts.lua): its texture is
	-- emptied, Blizzard only plays and recolors it.
	if tab.glow then
		tab.glow:SetTexture(nil)
	end

	-- Blizzard fades tabs down to 20%; the label and our pieces opt out of the
	-- tab's alpha so ApplyAlpha can keep them readable.
	local text = tab:GetFontString()
	SetLabelFont(text, tab)
	text:SetIgnoreParentAlpha(true)

	-- Center the label in the header. Blizzard puts it 11px above the tab's
	-- bottom (and further down on temporary windows); only the height changes.
	local point, relativeTo, relativePoint, x = text:GetPoint(1)
	local anchor = { point, relativeTo or tab, relativePoint, x, Theme.HEADER_HEIGHT / 2 - tab:GetHeight() / 2 }
	text:ClearAllPoints()
	text:SetPoint(unpack(anchor))
	-- Blizzard's tab is taller than the header, bottoms aligned: only its
	-- part over the header takes the mouse, so nothing unseen above the card
	-- catches a click.
	tab:SetHitRectInsets(0, 0, math.max(0, tab:GetHeight() - Theme.HEADER_HEIGHT), 0)
	-- Flat tabs: the label doesn't sink while pressed. A button shifts its
	-- label by the pushed offset on press and back on release; a label
	-- re-anchored in between (a tab's unread dot clears as the click opens it)
	-- was left 1.5 units off, up and to the left.
	tab:SetPushedTextOffset(0, 0)

	local px = PixelUtil.ConvertPixelsToUIForRegion(1, tab)
	local function Place(shape, bottom, left, right)
		shape:ClearAllPoints()
		shape:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", left or 0, bottom)
		shape:SetPoint("TOPRIGHT", tab, "BOTTOMRIGHT", -(right or 0), Theme.HEADER_HEIGHT)
		shape:SetIgnoreParentAlpha(true)
		return shape
	end

	local look = AddLook(tab, Place, px, Theme, true)
	look.glow:SetIgnoreParentAlpha(true)
	for _, pieces in ipairs({ look.pieces, look.left, { look.tail } }) do
		for _, piece in ipairs(pieces) do
			piece:SetIgnoreParentAlpha(true)
		end
	end

	local hover = Place(ns.Shapes.Fill(tab, "BACKGROUND", 0, Theme.TAB_RADIUS, "TOP"), 0)
	hover:SetColor(1, 1, 1, HOVER_ALPHA)
	hover:Hide()

	local parts = {
		tab = tab, text = text, anchor = anchor, shift = 0, look = look, hover = hover, chatFrame = chatFrame,
		selected = false, hovered = false, lit = 1, hoverFade = 0, hoverTarget = 0, leftFoot = false,
	}
	function parts.paintHover()
		hover:SetShown(parts.hoverFade > 0 and Framed())
		hover:SetAlpha(parts.hoverFade)
		UpdateTextColor(tab, parts)
	end
	tabParts[tab] = parts

	local function SetHovered(hovered)
		parts.hovered = hovered
		FadeHover(parts, (hovered and not parts.selected) and 1 or 0)
		ns.Header.SetHovered(tab, hovered and not parts.selected)
	end
	tab:HookScript("OnEnter", function()
		SetHovered(true)
	end)
	tab:HookScript("OnLeave", function()
		SetHovered(false)
	end)

	-- Same rule FCF uses when it calls FCFTab_UpdateColors.
	Tabs.UpdateSelection(tab, not chatFrame.isDocked or chatFrame == FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK))
	return parts
end

-- The tabs' look on another button (Options.lua's page tabs): the active
-- block in its gold frame whatever the chat's theme (the options window keeps
-- the game's gold), open into what's below, and the hover light. The button
-- stands on its row's bottom edge, like a chat tab, the row `height` tall.
function Tabs.CreateLook(button, height)
	height = height or Theme.HEADER_HEIGHT
	local px = PixelUtil.ConvertPixelsToUIForRegion(1, button)
	-- The block and the gold sides end flush with the line's lowest row, as
	-- they show on the chat's header (there they reach a pixel below it on
	-- paper; on the options window's whole-pixel row that pixel showed).
	local function Place(shape, bottom, left, right)
		shape:ClearAllPoints()
		shape:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", left or 0, math.max(bottom, 0))
		shape:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", -(right or 0), height)
		return shape
	end
	local active = AddLook(button, Place, px, Theme.GAME, true, height)
	PaintBlock(active, Theme.BODY.r, Theme.BODY.g, Theme.BODY.b, 0, Theme.BODY.r, Theme.BODY.g, Theme.BODY.b, FILL_ALPHA)
	active.tail:Hide()
	for _, piece in ipairs(active.left) do
		table.insert(active.pieces, piece)
	end
	local hover = Place(ns.Shapes.Fill(button, "BACKGROUND", 0, Theme.TAB_RADIUS, "TOP"), 0)
	hover:SetColor(1, 1, 1, HOVER_ALPHA)
	hover:Hide()
	local look = { active = active.pieces, hover = hover, hoverFade = 0, hoverTarget = 0 }
	function look.paintHover()
		hover:SetShown(look.hoverFade > 0)
		hover:SetAlpha(look.hoverFade)
	end
	function look:SetSelected(selected)
		for _, region in ipairs(self.active) do
			region:SetShown(selected)
		end
		self.selected = selected
		if selected then
			self.hoverFade = 0
		end
		FadeHover(self, (self.hovered and not selected) and 1 or 0)
	end
	function look:SetHovered(hovered)
		self.hovered = hovered
		FadeHover(self, (hovered and not self.selected) and 1 or 0)
	end
	look:SetSelected(false)
	return look
end

-- Tabs start at the panel's left edge. Docked tabs hang from the dock, which
-- Blizzard anchors to the primary window's Background in FCFDock_SetPrimary;
-- undocked tabs are placed by FCF_SetTabPosition. Both get the panel's offset.
-- The dock is the docked windows' header, so it takes the header's height
-- (its template's is the game's).
local function AlignDock(dock, primary)
	dock:SetPoint("BOTTOMLEFT", primary.Background, "TOPLEFT", -Theme.PANEL_PAD_LEFT, 0)
	dock:SetHeight(Theme.HEADER_HEIGHT)
end

function Tabs.AlignTab(chatFrame, x)
	local tab = _G[chatFrame:GetName() .. "Tab"]
	tab:ClearAllPoints()
	tab:SetPoint("BOTTOMLEFT", chatFrame.Background, "TOPLEFT", (x or 0) - Theme.PANEL_PAD_LEFT, 0)
end

-- The ghost in the theme: its frame or its lit line, and its name's color.
local function PaintGhost(ghost)
	local framed = Framed()
	PaintLook(ghost.look, Theme)
	for _, region in ipairs(ghost.look.pieces) do
		region:SetShown(framed)
	end
	local color = Theme.LINE
	for index, row in ipairs(ghost.lit) do
		row:SetColorTexture(color.r, color.g, color.b, index == 1 and Theme.LINE_LIT_ALPHA or Theme.LINE_LIT_SOFT_ALPHA)
		row:SetShown(not framed)
	end
	ghost.text:SetTextColor(Theme.TAB_OPEN:GetRGB())
end

-- A stand-in for a tab being dragged along the header: the active tab's look
-- (it's selected once dropped) with the tab's label. The caller sizes it.
function Tabs.CreateGhost(parent)
	local ghost = CreateFrame("Frame", nil, parent)
	ghost:SetHeight(Theme.HEADER_HEIGHT)
	local px = PixelUtil.ConvertPixelsToUIForRegion(1, ghost)

	local function Place(shape, bottom, left, right)
		shape:ClearAllPoints()
		shape:SetPoint("TOPLEFT", ghost, "TOPLEFT", left or 0, 0)
		shape:SetPoint("BOTTOMRIGHT", ghost, "BOTTOMRIGHT", -(right or 0), bottom)
		return shape
	end
	-- Like a skinned tab's, for Tabs.SetFillColor.
	ghost.look = AddLook(ghost, Place, px, Theme)
	Tabs.SetFillColor(ghost, Theme.BODY.r, Theme.BODY.g, Theme.BODY.b)

	local text = ghost:CreateFontString(nil, "ARTWORK")
	SetLabelFont(text)
	text:SetPoint("CENTER")
	ghost.text = text
	-- Without metal, the header line's two rows lit under it, as under the
	-- open tab (Skin.lua's trim).
	ghost.lit = {}
	for index = 1, 2 do
		local row = ghost:CreateTexture(nil, "ARTWORK")
		row:SetHeight(px)
		local y = (index - 1) * px
		row:SetPoint("BOTTOMLEFT", ghost, "BOTTOMLEFT", Theme.LINE_LIT_INSET, y)
		row:SetPoint("BOTTOMRIGHT", ghost, "BOTTOMRIGHT", -Theme.LINE_LIT_INSET, y)
		ghost.lit[index] = row
	end
	table.insert(ghosts, ghost)
	PaintGhost(ghost)
	ghost:Hide()
	return ghost
end

-- A new theme: the tabs' metal, their names and how the open one is marked.
local function Repaint()
	for tab, parts in pairs(tabParts) do
		PaintLook(parts.look, Theme)
		Tabs.UpdateSelection(tab, parts.selected)
	end
	for _, ghost in ipairs(ghosts) do
		PaintGhost(ghost)
	end
end

function Tabs.Init()
	AlignDock(GENERAL_CHAT_DOCK, GENERAL_CHAT_DOCK.primary)
	for _, name in pairs(CHAT_FRAMES) do
		local chatFrame = _G[name]
		if not chatFrame.isDocked then
			Tabs.AlignTab(chatFrame, 0)
		end
	end
	hooksecurefunc("FCFDock_SetPrimary", AlignDock)
	hooksecurefunc("FCF_SetTabPosition", Tabs.AlignTab)
	hooksecurefunc("FCFTab_UpdateColors", Tabs.UpdateSelection)
	Theme.OnChanged(Repaint)

end
