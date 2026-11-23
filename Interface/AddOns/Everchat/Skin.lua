local _, ns = ...
local Theme = ns.Theme

local Skin = {}
ns.Skin = Skin

-- Blizzard's soft window shadow, a round blob, cut into nine: its quadrants
-- are the corners and its middle row and column stretch along the edges. The
-- middle stays empty (the card covers it). Deeper below than above, as if lit
-- from above.
local SHADOW_ATLAS = "uitools-window-background-shadow"
local SHADOW_SIDE = 16
local SHADOW_TOP = 9
local SHADOW_BOTTOM = 22
local SHADOW_ALPHA = 0.8
-- The shadow blob's own darkness at its middle, where it meets the card:
-- black at 144/255.
local SHADOW_EDGE = 144 / 255

-- Extra space between wrapped lines, set through the chat frame's own API.
local LINE_SPACING = 2

local BLIZZARD_BORDER_TEXTURES = {
	"TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "TopTexture", "BottomTexture",
}

-- The side bar with the voice/chat buttons also inherits FloatingBorderedFrame.
local BUTTON_FRAME_TEXTURES = { "ButtonFrameBackground" }
for _, key in ipairs(BLIZZARD_BORDER_TEXTURES) do
	table.insert(BUTTON_FRAME_TEXTURES, "ButtonFrame" .. key)
end

-- Our state lives here, never as keys on Blizzard frames: writing into their
-- tables can spread taint into Blizzard code.
local chatSkins = {}
-- Header painted on Blizzard's dock, shared by every docked window.
local dockHeader

-- The edge a strip shares with the message area: a line in the theme's metal
-- on the strip's last row and a fainter one inside it, softening it (a lone
-- 1px line looked ruled, "web"), running whole from one side of the card to
-- the other, a divider ending square where the card's sides are straight
-- (ends fading to points read as decoration). On the last row the active
-- tab's frame ends on the line: a version with a shadow row under the line
-- put it a pixel off the tab, and one fading from the middle left it almost
-- invisible under the tabs. Inside the strip: the dock's pieces would be
-- under the chat frame's body past its edge. The options window's keeps the
-- game's gold (`palette`, Theme.GAME).
local TrimMixin = {}
-- Every trim but the options window's, to take a new theme's colors.
local themedTrims = {}

-- The header's line opens under the open tab (SetGap, from Header.lua and
-- for a floating window its own tab): two runs, from the card's sides to the
-- tab's, whose frame flows into them. Until v0.41.0 one line ran under the tab too and the tab's dark
-- block covered it; at rest, with the block gone (it made a darker box), the
-- line showed through and closed the tab (the user: open under the mouse,
-- a closed box at rest). Without a frame (Theme.OPEN_TAB_MARK "line") the
-- line runs whole and is lit under the open tab instead.
function TrimMixin:Paint()
	local palette = self.palette
	local color = palette.LINE
	for index, row in ipairs(self.rows) do
		-- The row's alpha in the texture's color: a vertex color's alpha is
		-- the texture's own (SetAlpha), which the fade sets.
		local alpha = index == 1 and palette.HEADER_LINE_ALPHA or palette.HEADER_LINE_SOFT_ALPHA
		row.middle:SetColorTexture(color.r, color.g, color.b, alpha)
		row.after:SetColorTexture(color.r, color.g, color.b, alpha)
		local lit = index == 1 and palette.LINE_LIT_ALPHA or palette.LINE_LIT_SOFT_ALPHA
		row.lit:SetColorTexture(color.r, color.g, color.b, lit)
		local hover = index == 1 and palette.LINE_HOVER_ALPHA or palette.LINE_HOVER_SOFT_ALPHA
		row.hover:SetColorTexture(color.r, color.g, color.b, hover)
	end
	self:PaintAlpha()
end

-- The chat's fade and the hover light only change the rows' alphas. A
-- hidden line (a docked window's own) waits for Layout, which shows it.
function TrimMixin:PaintAlpha()
	if not self.shown then
		return
	end
	local lit = self.litAlpha or self.alpha
	for _, row in ipairs(self.rows) do
		row.middle:SetAlpha(self.alpha)
		row.after:SetAlpha(self.alpha)
		row.lit:SetAlpha(lit)
		row.hover:SetAlpha(lit * self.hoverFade)
	end
end

function TrimMixin:Layout()
	local box, edge = self.box, self.edge
	local framed = self.palette.OPEN_TAB_MARK == "frame"
	local width = self.gapLeft and box:GetWidth()
	for index, row in ipairs(self.rows) do
		local function Place(texture, x, size)
			texture:ClearAllPoints()
			if size > 0 then
				texture:SetPoint(edge .. "LEFT", box, edge .. "LEFT", x, row.offset)
				texture:SetWidth(size)
			end
			texture:SetShown(self.shown and size > 0)
		end
		-- The open tab's span lit, a little in from its sides, and a tab's
		-- under the mouse.
		local function Span(texture, from, to)
			if not framed and from and box:GetWidth() > 0 then
				local full = box:GetWidth()
				local left = math.min(math.max(from + Theme.LINE_LIT_INSET, 0), full)
				local right = math.min(math.max(to - Theme.LINE_LIT_INSET, 0), full)
				Place(texture, left, right - left)
			else
				Place(texture, 0, 0)
			end
		end
		Span(row.lit, self.gapLeft, self.gapRight)
		Span(row.hover, self.hoverLeft, self.hoverRight)
		if framed and width and width > 0 then
			local from, to = self.gapLeft, self.gapRight
			if index > 1 then
				from, to = self.softLeft, self.softRight
			end
			local gapLeft = math.min(math.max(from, 0), width)
			local gapRight = math.min(math.max(to, 0), width)
			Place(row.middle, 0, gapLeft)
			Place(row.after, gapRight, width - gapRight)
		else
			-- Whole, anchored at both ends, so it follows the card's width by
			-- itself.
			row.middle:ClearAllPoints()
			row.middle:SetPoint(edge .. "LEFT", box, edge .. "LEFT", 0, row.offset)
			row.middle:SetPoint(edge .. "RIGHT", box, edge .. "RIGHT", 0, row.offset)
			row.middle:SetShown(self.shown)
			row.after:Hide()
		end
	end
	self:Paint()
end

-- `left` and `right` along the line from its left end; nil for no gap. The
-- row inside the line opens from `softLeft` to `softRight` (by default the
-- same; around the open tab's feet a little narrower, Tabs.OpenGap).
local function Same(a, b)
	return a == b or (a ~= nil and b ~= nil and math.abs(a - b) < 0.01)
end

function TrimMixin:SetGap(left, right, softLeft, softRight)
	if not (left and right and right > left) then
		left, right, softLeft, softRight = nil, nil, nil, nil
	end
	softLeft, softRight = softLeft or left, softRight or right
	if Same(left, self.gapLeft) and Same(right, self.gapRight)
		and Same(softLeft, self.softLeft) and Same(softRight, self.softRight) then
		return
	end
	self.gapLeft, self.gapRight, self.softLeft, self.softRight = left, right, softLeft, softRight
	self:Layout()
end

-- A tab under the mouse, along the line from its left end; nil for none.
-- Only drawn without a frame (Theme.LINE_HOVER_ALPHA). It lights up over a
-- moment and goes back the same way, as the tab's name does (Tabs.lua);
-- from one tab to the next it moves at once.
local HOVER_TIME = 0.12

local function StepHover(trim, elapsed)
	local step = elapsed / HOVER_TIME
	if trim.hoverTarget > trim.hoverFade then
		trim.hoverFade = math.min(trim.hoverTarget, trim.hoverFade + step)
	else
		trim.hoverFade = math.max(trim.hoverTarget, trim.hoverFade - step)
	end
	if trim.hoverFade == trim.hoverTarget then
		trim.driver:SetScript("OnUpdate", nil)
		if trim.hoverTarget == 0 then
			trim.hoverLeft, trim.hoverRight = nil, nil
			trim:Layout()
			return
		end
	end
	trim:PaintAlpha()
end

function TrimMixin:SetHover(left, right)
	if not (left and right and right > left) then
		left, right = nil, nil
	end
	local target = left and 1 or 0
	if target == self.hoverTarget and (target == 0 or (left == self.hoverLeft and right == self.hoverRight)) then
		return
	end
	if left then
		self.hoverLeft, self.hoverRight = left, right
	end
	self.hoverTarget = target
	self:Layout()
	self.driver:SetScript("OnUpdate", self.stepHover)
end

-- `litAlpha`: the stretch lit under the open tab, which marks the tab like
-- the metal frame does and so fades with it alone, not with the window's
-- background opacity as the line does (the line's alpha without it).
function TrimMixin:SetAlpha(alpha, litAlpha)
	self.alpha = alpha
	self.litAlpha = litAlpha
	self:PaintAlpha()
end

function TrimMixin:SetShown(shown)
	self.shown = shown
	self:Layout()
end

-- `fixed`: the game's gold whatever the theme (the options window).
local function CreateTrim(owner, box, edge, fixed)
	local px = PixelUtil.ConvertPixelsToUIForRegion(1, owner)
	local trim = CreateFromMixins(TrimMixin, {
		box = box, edge = edge, rows = {}, alpha = 1, shown = true, palette = fixed and Theme.GAME or Theme,
		hoverFade = 0, hoverTarget = 0,
	})
	-- Parentless, so the hover's fade ends even while the header is hidden.
	trim.driver = CreateFrame("Frame")
	trim.stepHover = function(_, elapsed)
		StepHover(trim, elapsed)
	end
	-- Colored by Paint.
	local function Piece()
		local texture = owner:CreateTexture(nil, "BORDER")
		texture:SetHeight(px)
		texture:SetColorTexture(1, 1, 1, 1)
		return texture
	end
	local function Row(offset)
		table.insert(trim.rows, {
			offset = offset,
			middle = Piece(),
			after = Piece(),
			lit = Piece(),
			hover = Piece(),
		})
	end
	Row(0)
	Row(edge == "BOTTOM" and px or -px)
	if not fixed then
		table.insert(themedTrims, trim)
	end
	-- Around a gap the runs are measured from the box's width, so they're
	-- laid out again whenever it changes (2026-10-14, on the user's 1080p
	-- laptop: the chat took its saved size after the first layout, and the
	-- line kept the old width, short of the card's end on a wide chat and
	-- running past it on a narrow one; SetGap alone only answered the open
	-- tab moving). A box is a texture, so a frame of ours watches its size.
	local watcher = CreateFrame("Frame", nil, owner)
	watcher:SetAllPoints(box)
	watcher:SetScript("OnSizeChanged", function()
		trim:Layout()
	end)
	trim:Layout()
	return trim
end

-- The header's fill opens under the open tab while it has its frame: the tab
-- paints that stretch itself, from the header's color at its top to the
-- message area's at its bottom (Tabs.lua), so it melts into both, at any
-- opacity (a block laid over the header's fill came out more opaque than
-- the message area under it). Whole, or a run on each side of the gap, each
-- with the card's corner at its outer end; a run too narrow for its corners
-- is a plain one.
local GapFillMixin = {}

for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth", "SetHeight" }) do
	GapFillMixin[method] = function(self, ...)
		self.box[method](self.box, ...)
	end
end

-- Only the pieces on show are painted (the chat's fade repaints the header
-- on every step); Layout paints what it shows.
function GapFillMixin:Paint()
	local color, visible = self.color, self.visible
	if not color[1] then
		return
	end
	for _, fill in ipairs(self.fills) do
		if visible[fill] then
			fill:SetColor(color[1], color[2], color[3], color[4])
		end
	end
	for _, plain in ipairs(self.plains) do
		if visible[plain] then
			plain:SetColorTexture(color[1], color[2], color[3], color[4])
		end
	end
end

function GapFillMixin:Layout()
	local width = self.box:GetWidth()
	local runs = self.gapLeft ~= nil and width > 0
	local visible = self.visible
	visible[self.whole] = self.shown and not runs
	local function Run(fill, plain, size)
		local show = self.shown and runs and size > 0
		if show then
			fill:SetWidth(size)
			plain:SetWidth(size)
		end
		visible[fill] = show and size >= self.minRun
		visible[plain] = show and size < self.minRun
	end
	local left = runs and math.min(math.max(self.gapLeft, 0), width) or 0
	local right = runs and math.min(math.max(self.gapRight, 0), width) or width
	Run(self.left, self.leftPlain, left)
	Run(self.right, self.rightPlain, width - right)
	for region, shown in pairs(visible) do
		region:SetShown(shown)
	end
	self:Paint()
end

-- `left` and `right` along the header from its left end; nil for none.
-- `leftFoot` and `rightFoot`: the run ending there rounds into the open tab's
-- foot (Tabs.lua, Theme.TAB_FOOT); without one (the tab cut off at the
-- strip's end) it ends square.
function GapFillMixin:SetGap(left, right, leftFoot, rightFoot)
	if not (left and right and right > left) then
		left, right = nil, nil
	end
	leftFoot, rightFoot = leftFoot and true or false, rightFoot and true or false
	if leftFoot ~= self.leftFoot then
		self.leftFoot = leftFoot
		self.left:SetCornerRadius("BOTTOMRIGHT", leftFoot and Theme.TAB_FOOT or nil)
	end
	if rightFoot ~= self.rightFoot then
		self.rightFoot = rightFoot
		self.right:SetCornerRadius("BOTTOMLEFT", rightFoot and Theme.TAB_FOOT or nil)
	end
	if left == self.gapLeft and right == self.gapRight then
		return
	end
	self.gapLeft, self.gapRight = left, right
	self:Layout()
end

function GapFillMixin:SetColor(r, g, b, a)
	local color = self.color
	color[1], color[2], color[3], color[4] = r, g, b, a or 1
	self:Paint()
end

function GapFillMixin:SetShown(shown)
	self.shown = shown
	self:Layout()
end

local function CreateGapFill(owner, layer, radius)
	local fill = CreateFromMixins(GapFillMixin, {
		shown = true, leftFoot = false, rightFoot = false, color = {}, visible = {},
	})
	fill.box = owner:CreateTexture(nil, layer)
	fill.box:SetColorTexture(0, 0, 0, 0)
	fill.whole = ns.Shapes.Fill(owner, layer, 0, radius, "TOP")
	fill.whole:SetAllPoints(fill.box)
	local function Side(rounded, point)
		local run = ns.Shapes.Fill(owner, layer, 0, radius, rounded)
		run:SetPoint("TOP" .. point, fill.box, "TOP" .. point)
		run:SetPoint("BOTTOM" .. point, fill.box, "BOTTOM" .. point)
		local plain = owner:CreateTexture(nil, layer)
		plain:SetPoint("TOP" .. point, fill.box, "TOP" .. point)
		plain:SetPoint("BOTTOM" .. point, fill.box, "BOTTOM" .. point)
		return run, plain
	end
	fill.left, fill.leftPlain = Side("TOPLEFT", "LEFT")
	fill.right, fill.rightPlain = Side("TOPRIGHT", "RIGHT")
	fill.fills = { fill.whole, fill.left, fill.right }
	fill.plains = { fill.leftPlain, fill.rightPlain }
	fill.minRun = 2 * radius * PixelUtil.ConvertPixelsToUIForRegion(1, owner)
	local watcher = CreateFrame("Frame", nil, owner)
	watcher:SetAllPoints(fill.box)
	watcher:SetScript("OnSizeChanged", function()
		fill:Layout()
	end)
	fill:Layout()
	return fill
end

-- A strip of the card (header or footer): a fill with the card's outer corners
-- rounded, trimmed on the edge it shares with the message area. The caller
-- places the fill (the header's can open under the open tab: SetGap).
local function CreateStrip(owner, sharedEdge)
	local fill
	if sharedEdge == "BOTTOM" then
		fill = CreateGapFill(owner, "BACKGROUND", Theme.CARD_RADIUS)
	else
		fill = ns.Shapes.Fill(owner, "BACKGROUND", 0, Theme.CARD_RADIUS, "BOTTOM")
	end
	fill:SetColor(Theme.HEADER:GetRGBA())
	return fill, CreateTrim(owner, fill.box, sharedEdge)
end

-- The card's header strip, and the trim alone (under the options window's
-- page tabs).
Skin.CreateStrip = CreateStrip
Skin.CreateTrim = CreateTrim

-- A box set into the footer (the edit box's field, the padlock button): a
-- darker rounded fill with a 1px edge, in the owner's given layers. The caller
-- places inset.box; fill and edge follow it.
function Skin.CreateInset(owner, fillLayer, edgeLayer)
	local inset = {}
	inset.fill = ns.Shapes.Fill(owner, fillLayer, 2, Theme.INSET_RADIUS)
	inset.fill:SetColor(Theme.FIELD:GetRGBA())
	inset.box = inset.fill.box
	inset.edge = ns.Shapes.Outline(owner, edgeLayer, 0, Theme.INSET_RADIUS)
	inset.edge.box:SetAllPoints(inset.box)
	inset.edge:SetColor(Theme.FIELD_EDGE:GetRGBA())

	function inset:SetEdgeColor(r, g, b, a)
		self.edge:SetColor(r, g, b, a)
	end
	return inset
end

-- Every hairline but the options window's, to take a new theme's color.
local themedHairlines = {}

-- A piece of the game's shadow blob, by where it is in the blob.
local function ShadowPiece(frame, u1, u2, v1, v2)
	local info = C_Texture.GetAtlasInfo(SHADOW_ATLAS)
	local piece = frame:CreateTexture(nil, "BACKGROUND")
	piece:SetTexture(info.file or info.filename)
	local left, right = info.leftTexCoord, info.rightTexCoord
	local upper, lower = info.topTexCoord, info.bottomTexCoord
	piece:SetTexCoord(Lerp(left, right, u1), Lerp(left, right, u2), Lerp(upper, lower, v1), Lerp(upper, lower, v2))
	piece:SetVertexColor(1, 1, 1, SHADOW_ALPHA)
	return piece
end

-- A card's corner is round and the shadow goes around its square: the bit of
-- the corner the curve leaves out was under neither, and showed the world
-- unshaded, a light notch in the shadow. It takes the shadow's darkness at the
-- card's edge, exactly what the corner's art leaves out (Media/Notch6, its
-- complement), so a see-through card shows nothing more under itself.
local function ShadowNotch(frame, region, point)
	local notch = ns.Shapes.Corner(frame, "BACKGROUND", 0, "Notch", Theme.CARD_RADIUS, point)
	notch:SetPoint(point, region, point)
	notch:SetVertexColor(0, 0, 0, SHADOW_EDGE * SHADOW_ALPHA)
	return notch
end

Skin.ShadowPiece = ShadowPiece
Skin.ShadowNotch = ShadowNotch

-- The shadow and a faint light hairline around the card, from the header's
-- top-left to the footer's bottom-right. On its own frame on the BACKGROUND
-- strata, so it never covers the docked tabs (LOW, like the chat frame).
-- `fixed`: the hairline in the game's gold whatever the theme. `window`: as
-- the game's own windows end, only a dark line close around the edge, with
-- the ground untouched past it (the shadow's square around the round corners
-- made them look square).
local WINDOW_EDGE = { 0, 0, 0, 0.7 }

local function CreateShadow(chatFrame, top, bottom, fixed, window)
	local frame = CreateFrame("Frame", nil, chatFrame)
	frame:SetFrameStrata("BACKGROUND")
	frame:SetFrameLevel(0)
	local px = PixelUtil.ConvertPixelsToUIForRegion(1, chatFrame)

	-- The hairline, 1px outside the card, its corners 1px rounder.
	local hairline = ns.Shapes.Outline(frame, "ARTWORK", 0, Theme.CARD_RADIUS + 1)
	hairline:SetPoint("TOPLEFT", top, "TOPLEFT", -px, px)
	hairline:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", px, -px)
	if window then
		hairline:SetColor(unpack(WINDOW_EDGE))
		return frame
	end
	hairline:SetColor((fixed and Theme.GAME or Theme).HAIRLINE:GetRGBA())
	if not fixed then
		table.insert(themedHairlines, hairline)
	end

	local side, above, below = SHADOW_SIDE, SHADOW_TOP, SHADOW_BOTTOM
	local function Piece(u1, u2, v1, v2)
		return ShadowPiece(frame, u1, u2, v1, v2)
	end

	local topLeft = Piece(0, 0.5, 0, 0.5)
	topLeft:SetPoint("BOTTOMRIGHT", top, "TOPLEFT")
	topLeft:SetSize(side, above)
	local topRight = Piece(0.5, 1, 0, 0.5)
	topRight:SetPoint("BOTTOMLEFT", top, "TOPRIGHT")
	topRight:SetSize(side, above)
	local bottomLeft = Piece(0, 0.5, 0.5, 1)
	bottomLeft:SetPoint("TOPRIGHT", bottom, "BOTTOMLEFT")
	bottomLeft:SetSize(side, below)
	local bottomRight = Piece(0.5, 1, 0.5, 1)
	bottomRight:SetPoint("TOPLEFT", bottom, "BOTTOMRIGHT")
	bottomRight:SetSize(side, below)

	local topEdge = Piece(0.5, 0.5, 0, 0.5)
	topEdge:SetPoint("TOPLEFT", topLeft, "TOPRIGHT")
	topEdge:SetPoint("BOTTOMRIGHT", topRight, "BOTTOMLEFT")
	local bottomEdge = Piece(0.5, 0.5, 0.5, 1)
	bottomEdge:SetPoint("TOPLEFT", bottomLeft, "TOPRIGHT")
	bottomEdge:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMLEFT")
	local leftEdge = Piece(0, 0.5, 0.5, 0.5)
	leftEdge:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT")
	leftEdge:SetPoint("BOTTOMRIGHT", bottomLeft, "TOPRIGHT")
	local rightEdge = Piece(0.5, 1, 0.5, 0.5)
	rightEdge:SetPoint("TOPLEFT", topRight, "BOTTOMLEFT")
	rightEdge:SetPoint("BOTTOMRIGHT", bottomRight, "TOPRIGHT")

	for point, region in pairs({ TOPLEFT = top, TOPRIGHT = top, BOTTOMLEFT = bottom, BOTTOMRIGHT = bottom }) do
		ShadowNotch(frame, region, point)
	end

	return frame
end

-- The card's shadow and hairline around any region (Buttons.lua's rail too).
Skin.CreateShadow = CreateShadow

-- The game's own Background setting (a tab's menu > Background: a color
-- and an opacity slider) sets the card's color and how solid it is.
-- Opacity: its default (25%) is Everchat's look; below it the card fades out
-- with the slider, down to just the text at 0, and above it the fills reach
-- full opacity at 100%. Lines, shadow and hairline fade with the fills, so a
-- clear chat has no card left. Color: the default black is Everchat's warm
-- black; any other color tints the card dark (a bright color at the card's
-- 89% would bury the text), the header a little lighter.
-- Read with GetChatWindowInfo, then from FCF_SetWindowColor/Alpha's own
-- arguments (post-hooked): Blizzard saves a picked color only after
-- FCF_SetWindowColor returns. (Blizzard's own Background texture, which the
-- setting used to tint, is emptied.)
local DEFAULT_OPACITY = DEFAULT_CHATFRAME_ALPHA or 0.25
-- How dark a picked color is drawn, and how much lighter the header is.
local TINT = 0.22
local HEADER_TINT = 0.32
local HEADER_LIFT = 0.05
-- By chat frame: { r, g, b, alpha } as the game has them.
local looks = {}

local function LookOf(chatFrame)
	local look = looks[chatFrame]
	if not look then
		local _, _, r, g, b, alpha = GetChatWindowInfo(chatFrame:GetID())
		look = { r = r or 0, g = g or 0, b = b or 0, alpha = alpha or DEFAULT_OPACITY }
		looks[chatFrame] = look
	end
	return look
end

local function OpacityOf(chatFrame)
	return LookOf(chatFrame).alpha
end

-- The body's and the header's colors for the window's setting.
local function CardColors(chatFrame)
	local look = LookOf(chatFrame)
	if look.r + look.g + look.b < 0.02 then
		return Theme.BODY.r, Theme.BODY.g, Theme.BODY.b, Theme.HEADER.r, Theme.HEADER.g, Theme.HEADER.b
	end
	return look.r * TINT, look.g * TINT, look.b * TINT,
		look.r * HEADER_TINT + HEADER_LIFT, look.g * HEADER_TINT + HEADER_LIFT, look.b * HEADER_TINT + HEADER_LIFT
end

-- Opens a header's line and fill around the open tab, from `left` to
-- `right` along it (nil: none), its side cut off at `limit`: with the frame,
-- around its feet (Tabs.OpenGap); without, the line runs whole, lit there.
local function OpenHeader(fill, line, left, right, limit, px)
	if left and Theme.OPEN_TAB_MARK == "frame" then
		local gap = ns.Tabs.OpenGap(left, right, px, limit)
		line:SetGap(gap.lineLeft, gap.lineRight, gap.softLeft, gap.softRight)
		fill:SetGap(gap.fillLeft, gap.fillRight, gap.leftFoot, gap.rightFoot)
	else
		line:SetGap(left, right)
		fill:SetGap(nil)
	end
end

-- The open docked tab's span along the dock's header, from its left end, and
-- the end of the strip showing the tabs, or nil while it's out of view
-- (Header.lua).
local headerGap = {}

function Skin.SetHeaderGap(left, right, limit)
	headerGap.left, headerGap.right, headerGap.limit = left, right, limit
	if dockHeader then
		OpenHeader(dockHeader[1], dockHeader[2], left, right, limit, PixelUtil.ConvertPixelsToUIForRegion(1, GENERAL_CHAT_DOCK))
	end
end

-- A docked tab under the mouse, its span along the dock's header (nil for
-- none): without a frame its stretch of the line lights up.
function Skin.SetHeaderHover(left, right)
	if dockHeader then
		dockHeader[2]:SetHover(left, right)
	end
end

-- The window's body color (Header.lua's drag ghost, the tab it stands for).
function Skin.BodyColor(chatFrame)
	local r, g, b = CardColors(chatFrame)
	return r, g, b
end

-- A fill's alpha for the setting: its own alpha at the default.
local function FillAlpha(base, opacity)
	if opacity <= DEFAULT_OPACITY then
		return base * opacity / DEFAULT_OPACITY
	end
	return base + (1 - base) * (opacity - DEFAULT_OPACITY) / (1 - DEFAULT_OPACITY)
end

-- How much of the lines and shadow show for the setting.
local function OverlayFactor(opacity)
	return math.min(1, opacity / DEFAULT_OPACITY)
end

local function Mix(from, to, t)
	return from + (to - from) * t
end

-- How much of the message area's fill stays at rest: the card's own resting
-- level, or more when the window's opacity asks for more. The game's chat
-- rests at the opacity set in the tab's menu, so a chat made solid to be
-- read never rests see-through.
local function RestLevel(fillAlpha, opacity)
	if Theme.hiddenAtRest then
		return 0
	end
	if fillAlpha <= 0 then
		return Theme.REST_BODY
	end
	return math.max(Theme.REST_BODY, math.min(1, opacity / fillAlpha))
end

-- A strip's color at `lit` (Theme.REST_*): under the mouse the header's own,
-- at rest the message area's color and resting alpha, so the card rests as
-- one plain shape. `colors` holds { body = {r, g, b, a}, header = {...},
-- rest = the message area's resting level }.
local function StripColor(colors, lit)
	local body, header = colors.body, colors.header
	-- The minimal style: one surface, the message area's look lit or not.
	if Theme.STRIP_AS_BODY then
		return body[1], body[2], body[3], body[4] * Theme.Rest(colors.rest, lit)
	end
	return Mix(body[1], header[1], lit), Mix(body[2], header[2], lit), Mix(body[3], header[3], lit),
		Mix(body[4] * colors.rest, header[4], lit)
end

-- Hidden at rest (Theme.hiddenAtRest, the options' "Chat when idle: Hidden"
-- idle"), the whole chat goes and new messages show for the seconds chosen
-- beside it (LINES_VISIBLE by default), then fade over LINES_FADE: the
-- frame's own line fading, which the game itself turns off while a chat
-- frame has the gamepad's focus.
local LINES_VISIBLE = 10
local LINES_FADE = 3

local function LinesVisible()
	return ns.db.hideAtRestSeconds or LINES_VISIBLE
end
-- It comes back from the bottom up, as a panel opens: the field, then the
-- messages, then the header, each zone starting a fifth of the way after the
-- one below; it goes the other way. It comes in over HIDDEN_FADE_IN, longer
-- than the game's fade, so the order shows.
local CASCADE = 0.4
local HIDDEN_FADE_IN = 0.3

-- `lit` for a zone of the card, from 0 (the footer) to 2 (the header).
local function ZoneLit(lit, zone)
	if not Theme.hiddenAtRest then
		return lit
	end
	return math.max(0, math.min(1, (lit - zone * CASCADE / 2) / (1 - CASCADE)))
end

-- The lines brought back on waking, when none was left in sight: they fade
-- in with the messages' zone (their crests and portraits with them) instead
-- of appearing at once.
local function RevealLines(skin, alpha)
	local container = skin.chatFrame.FontStringContainer
	if container then
		container:SetAlpha(alpha)
	end
	ns.Channels.SetMarksAlpha(skin.chatFrame, alpha)
	if alpha >= 1 then
		skin.revealing = nil
	end
end

-- Hidden at rest, with nothing around the messages, the one cut through by
-- the frame's top edge looked cut off. It fades out with the header, and once
-- the header is gone the messages are clipped just above the highest one
-- wholly in the frame, so only whole messages show (the frame's
-- FontStringContainer clips its lines; the crests' overlay follows it).
local CLIP_MARGIN = 0.5

local function SetClipInset(skin, inset)
	local container = skin.chatFrame.FontStringContainer
	if inset == skin.clipInset or not container then
		return
	end
	skin.clipInset = inset
	container:ClearAllPoints()
	container:SetPoint("TOPLEFT", skin.chatFrame, "TOPLEFT", 0, -inset)
	container:SetPoint("BOTTOMRIGHT", skin.chatFrame, "BOTTOMRIGHT")
end

-- `alpha`: the header's, which the cut message takes.
-- A readable number: a line that drew a secret message can answer with secret
-- measures, whatever it shows now.
local function IsNumber(value)
	return type(value) == "number" and canaccessvalue(value)
end

local function EdgeLines(skin, alpha)
	skin.edgeAlpha = alpha
	local chatFrame = skin.chatFrame
	local top = chatFrame:GetTop()
	if not IsNumber(top) then
		return
	end
	local cut, highest
	for _, line in ipairs(chatFrame.visibleLines or {}) do
		local lineTop, lineBottom = line:GetTop(), line:GetBottom()
		if line:IsShown() and IsNumber(lineTop) and IsNumber(lineBottom) then
			if lineTop <= top then
				highest = math.max(highest or lineTop, lineTop)
			elseif lineBottom < top then
				cut = line
			end
		end
	end
	if cut then
		cut:SetAlpha(alpha)
	end
	local clipped = alpha == 0 and not skin.awake and highest
	SetClipInset(skin, clipped and math.max(0, top - highest - CLIP_MARGIN) or 0)
end

-- The docked tabs stand in one header, so they all go with the window on show,
-- as the header and the card do. By its own fade a hidden window's tab went out
-- while the window on show was held lit (typing, resizing, searching): the game
-- fades every docked window when the mouse leaves, and only one is held.
local dockTabsLit = 0

-- `lit` goes from 0 (at rest) to 1 (under the mouse, typing, resizing).
local function ApplyChrome(skin, lit)
	skin.lit = lit
	local footerLit, bodyLit, headerLit = ZoneLit(lit, 0), ZoneLit(lit, 1), ZoneLit(lit, 2)
	-- When the docked chat fades the game fades every docked window, the
	-- hidden ones too: the window on show paints their tabs, and the rest is
	-- painted when the window is shown (its OnShow). Painting every card on
	-- every frame of the fade cost a sixth of the frame with seven tabs.
	if not skin.chatFrame:IsShown() then
		local tabLit = skin.chatFrame.isDocked and dockTabsLit or headerLit
		if skin.tabLit ~= tabLit then
			skin.tabLit = tabLit
			ns.Tabs.ApplyAlpha(skin.tab, tabLit, skin.overlayFactor or 1)
		end
		return
	end
	skin.body:SetAlpha(Theme.Rest(skin.colors and skin.colors.rest or Theme.REST_BODY, bodyLit))
	if skin.colors then
		skin.headerFill:SetColor(StripColor(skin.colors, headerLit))
		skin.footerFill:SetColor(StripColor(skin.colors, footerLit))
	end
	local openTab = Theme.Rest(Theme.REST_OPEN_TAB, headerLit)
	skin.headerLine:SetAlpha(openTab * (skin.overlayFactor or 1), openTab)
	for _, region in ipairs(skin.overlays) do
		region:SetAlpha(bodyLit * (skin.overlayFactor or 1))
	end
	-- The minimal style lies flat.
	skin.shadow:SetShown(Theme.CARD_SHADOW)
	local controls = Theme.Rest(Theme.REST_CONTROLS, footerLit)
	for _, region in ipairs(skin.chrome) do
		region:SetAlpha(controls)
	end
	for _, region in ipairs(skin.controls) do
		region:SetAlpha(controls)
	end
	for _, region in ipairs(skin.openTab) do
		region:SetAlpha(openTab)
	end
	if skin.chatFrame.isDocked and dockHeader and dockHeader.colors then
		local r, g, b, a = StripColor(dockHeader.colors, headerLit)
		dockHeader[1]:SetColor(r, g, b, a)
		dockHeader[2]:SetAlpha(openTab * (dockHeader.overlayFactor or 1), openTab)
		-- The edge shading over clipped tabs: opaque under the mouse, as
		-- see-through as the header at rest; always as the header when it's
		-- drawn as the message area.
		local shade = Theme.STRIP_AS_BODY and a or Mix(dockHeader.colors.body[4] * dockHeader.colors.rest, 1, headerLit)
		ns.Header.ApplyAlpha(headerLit, r, g, b, shade)
		-- The side bar, as tall as the card, comes with the messages.
		ns.Buttons.ApplyAlpha(bodyLit, StripColor(dockHeader.colors, bodyLit))
	end
	-- The open tab's block, from the header's look at its top to the message
	-- area's at its bottom (the header's fill is open under it).
	if skin.colors then
		local r, g, b, a = StripColor(skin.colors, headerLit)
		local body = skin.colors.body
		ns.Tabs.SetBlockColors(skin.tab, r, g, b, a, body[1], body[2], body[3], body[4] * Theme.Rest(skin.colors.rest, bodyLit))
	end
	if skin.revealing then
		RevealLines(skin, bodyLit)
	end
	if Theme.hiddenAtRest then
		EdgeLines(skin, headerLit)
	end
	ns.Scroll.SetFade(skin.chatFrame, Theme.Rest(1, bodyLit))
	skin.tabLit = headerLit
	ns.Tabs.ApplyAlpha(skin.tab, headerLit, skin.overlayFactor or 1)
	if skin.chatFrame.isDocked then
		dockTabsLit = headerLit
		for _, frame in ipairs(FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)) do
			local other = chatSkins[frame]
			if other and other ~= skin and other.tabLit ~= headerLit then
				other.tabLit = headerLit
				ns.Tabs.ApplyAlpha(other.tab, headerLit, other.overlayFactor or 1)
			end
		end
	end
end

-- Each window's line fading as the game set it, while hidden at rest
-- changes it.
local gameFading = {}

-- Hidden at rest: every line shows while the chat is in use; at rest the
-- lines stay the chosen seconds more, then fade, and so do new ones.
local function SetLinesAtRest(skin, atRest)
	local chatFrame = skin.chatFrame
	if not gameFading[chatFrame] then
		gameFading[chatFrame] = { chatFrame:GetFading(), chatFrame:GetTimeVisible(), chatFrame:GetFadeDuration() }
	end
	if atRest then
		chatFrame:SetTimeVisible(LinesVisible())
		chatFrame:SetFadeDuration(LINES_FADE)
		chatFrame:SetFading(true)
		chatFrame:ResetAllFadeTimes()
		skin.linesUntil = GetTime() + LinesVisible() + LINES_FADE
	else
		chatFrame:SetFading(false)
	end
end

local function RestoreLines(skin)
	local chatFrame = skin.chatFrame
	local game = gameFading[chatFrame]
	if game then
		gameFading[chatFrame] = nil
		chatFrame:SetFading(game[1])
		chatFrame:SetTimeVisible(game[2])
		chatFrame:SetFadeDuration(game[3])
		chatFrame:ResetAllFadeTimes()
	end
end

-- Lines only fade at the bottom of the chat: one left scrolled up goes back
-- down once it's hidden.
local function LinesToBottom(skin)
	local chatFrame = skin.chatFrame
	if chatFrame:IsShown() and not chatFrame:AtBottom() then
		chatFrame:ScrollToBottom()
		skin.linesUntil = GetTime() + LinesVisible() + LINES_FADE
	end
end

-- Hidden at rest, waking and going to rest also bring the lines back and
-- let them go.
local function Wake(skin, awake)
	if awake == skin.awake then
		return
	end
	skin.awake = awake
	if awake then
		-- The cut message comes back with the header (ApplyChrome).
		EdgeLines(skin, ZoneLit(skin.lit, 2))
		if skin.chatFrame ~= COMBATLOG and skin.chatFrame:IsShown() and GetTime() > (skin.linesUntil or 0) then
			skin.revealing = true
			RevealLines(skin, ZoneLit(skin.lit, 1))
		end
		SetLinesAtRest(skin, false)
	else
		if skin.revealing then
			RevealLines(skin, 1)
		end
		SetLinesAtRest(skin, true)
	end
end

-- Steps of the fade smaller than this aren't painted: the fade to rest takes
-- two seconds, and between two frames of it nothing visible changes.
local FADE_STEP = 0.02

-- Own fade instead of UIFrameFadeIn/Out: those share a Blizzard table, and
-- inserting our frames there would taint every fade the game runs. The driver
-- is parentless so it keeps ticking for docked windows that are hidden.
local function FadeTo(skin, target, duration)
	local from = skin.lit
	if Theme.hiddenAtRest then
		Wake(skin, target > 0)
		if target > from then
			duration = math.max(duration, HIDDEN_FADE_IN)
		end
	end
	if duration <= 0 or from == target then
		skin.driver:SetScript("OnUpdate", nil)
		ApplyChrome(skin, target)
		return
	end

	local elapsedTotal = 0
	skin.driver:SetScript("OnUpdate", function(self, elapsed)
		elapsedTotal = elapsedTotal + elapsed
		local progress = math.min(elapsedTotal / duration, 1)
		if progress == 1 then
			self:SetScript("OnUpdate", nil)
			ApplyChrome(skin, target)
			if Theme.hiddenAtRest and target == 0 then
				LinesToBottom(skin)
			end
			return
		end
		local lit = from + (target - from) * progress
		if math.abs(lit - skin.lit) >= FADE_STEP then
			ApplyChrome(skin, lit)
		end
	end)
end

-- Typing or resizing keeps the whole chat lit, even if the mouse leaves it.
-- When the last hold ends, it fades back unless the mouse is over the chat
-- (then Blizzard's own fade-out takes over later).
-- Whether the player is attending the chat, which a tab's sound asks. Just
-- after typing still counts, and a mouse left still on the chat stops counting
-- after a while: it may simply be parked there. Only read as a line arrives,
-- so the mouse is compared with where it was last seen.
local TYPING_GRACE = 3
local MOUSE_STILL = 20
local typing, typedAt = false, nil
local mouseX, mouseY, mouseAt

local function NoteMouse()
	mouseX, mouseY = GetCursorPosition()
	mouseAt = GetTime()
end

local function MouseIsActive()
	local x, y = GetCursorPosition()
	if not mouseAt or x ~= mouseX or y ~= mouseY then
		mouseX, mouseY, mouseAt = x, y, GetTime()
		return true
	end
	return GetTime() - mouseAt < MOUSE_STILL
end

function Skin.TypedRecently()
	return typing or (typedAt ~= nil and GetTime() - typedAt < TYPING_GRACE)
end

function Skin.IsChatInUse(chatFrame)
	if Skin.TypedRecently() then
		return true
	end
	local skin = chatSkins[chatFrame]
	if not skin then
		return false
	end
	local holds = skin.holds
	if holds.search or holds.resizing or holds.moving then
		return true
	end
	-- Never by the chat being lit: Always Visible holds it so.
	return (chatFrame.hasBeenFaded or holds.hover) and MouseIsActive() or false
end

function Skin.Hold(skin, reason, held)
	if reason == "hover" and held then
		NoteMouse()
	end
	skin.holds[reason] = held or nil
	if next(skin.holds) then
		FadeTo(skin, 1, CHAT_FRAME_FADE_TIME)
	elseif not skin.chatFrame.hasBeenFaded then
		FadeTo(skin, 0, CHAT_FRAME_FADE_OUT_TIME)
	end
end

-- Always visible: the chat held lit as while typing, whatever Blizzard's fade
-- does, and the messages kept in sight (the frame's own switch, as the game
-- does while a chat frame has the gamepad's focus). No fade runs at all.
local restAlways = false

local function KeepInSight(skin)
	Skin.Hold(skin, "always", true)
	local chatFrame = skin.chatFrame
	if not gameFading[chatFrame] then
		gameFading[chatFrame] = { chatFrame:GetFading(), chatFrame:GetTimeVisible(), chatFrame:GetFadeDuration() }
	end
	chatFrame:SetFading(false)
end

-- The mouse on the chat brings its messages back for the game's usual time: the
-- game only does so on a scroll, and a lit card with nothing on it looks broken.
-- Hidden at rest and Always Visible see to the lines themselves.
local function BringLinesBack(skin)
	if not Theme.hiddenAtRest and not skin.holds.always and skin.chatFrame:IsShown() then
		skin.chatFrame:ResetAllFadeTimes()
	end
end

-- The mouse anywhere on the card, from the header to the footer and the side
-- bar, brings it back (the game only looks at the message area). Hidden at
-- rest, by the game's own rule: once the cursor stays still over it for
-- CHAT_TAB_SHOW_DELAY, so passing over it does nothing. Faded, sooner: once it
-- has been over it for QUICK_SHOW, moving or not (waiting for it to stop made
-- the chat feel slow to answer). Either way gone after CHAT_TAB_HIDE_DELAY
-- away. Not with Always Visible, which has nothing to bring back.
local QUICK_SHOW = 0.1
local HOVER_TOP = Theme.HEADER_HEIGHT + 4
local HOVER_BOTTOM = Theme.FOOTER_HEIGHT + 8
local HOVER_SIDE = Theme.PANEL_PAD_LEFT + 4
local hoverWatcher = CreateFrame("Frame")
local lastCursorX, lastCursorY

local function MouseOverCard(chatFrame)
	return chatFrame:IsShown() and (chatFrame:IsMouseOver(HOVER_TOP, -HOVER_BOTTOM, -HOVER_SIDE, HOVER_SIDE)
		or (chatFrame.isDocked and ns.Buttons.IsMouseOver()))
end

-- Whether the mouse is anywhere on a window's card (Resize.lua's lock).
function Skin.IsMouseOverCard(chatFrame)
	return chatFrame ~= nil and MouseOverCard(chatFrame)
end

local function WatchHover(_, elapsed)
	local x, y = GetCursorPosition()
	local still = x == lastCursorX and y == lastCursorY
	lastCursorX, lastCursorY = x, y
	for chatFrame, skin in pairs(chatSkins) do
		if MouseOverCard(chatFrame) then
			skin.hoverAway = 0
			if not skin.holds.hover then
				local wait = QUICK_SHOW
				if Theme.hiddenAtRest then
					wait = CHAT_TAB_SHOW_DELAY or 0.2
					skin.hoverStill = still and (skin.hoverStill or 0) + elapsed or 0
				else
					skin.hoverStill = (skin.hoverStill or 0) + elapsed
				end
				if skin.hoverStill > wait then
					skin.hoverStill = nil
					Skin.Hold(skin, "hover", true)
				end
			end
		elseif skin.holds.hover then
			skin.hoverAway = (skin.hoverAway or 0) + elapsed
			if skin.hoverAway > (CHAT_TAB_HIDE_DELAY or 1) then
				skin.hoverAway = nil
				Skin.Hold(skin, "hover", false)
			end
		else
			skin.hoverStill = nil
		end
	end
end

-- The same, for whichever window is showing (the dock's selected one).
function Skin.HoldWindow(chatFrame, reason, held)
	local skin = chatFrame and chatSkins[chatFrame]
	if skin then
		Skin.Hold(skin, reason, held)
	end
end

function Skin.SetTyping(skin, focused)
	skin.hint:SetShown(not focused)
	Skin.Hold(skin, "typing", focused)
	if typing and not focused then
		typedAt = GetTime()
	end
	typing = focused and true or false
end

-- One card resting on a soft shadow: a header for the tabs, the message area,
-- and a footer holding the edit box's field. Anchored to Blizzard's Background,
-- which they re-anchor when the scrollbar or combat log buttons change.
local function CreatePanel(chatFrame)
	local body = chatFrame:CreateTexture(nil, "BACKGROUND")
	body:SetPoint("TOPLEFT", chatFrame.Background, "TOPLEFT", -Theme.PANEL_PAD_LEFT, 0)
	body:SetPoint("BOTTOMRIGHT", chatFrame.Background, "BOTTOMRIGHT")
	body:SetColorTexture(Theme.BODY:GetRGBA())

	-- This window's own header, only shown while it's undocked: its tab then
	-- sits on a higher strata than the chat frame. Docked tabs sit below the
	-- chat frame, so docked windows use the header painted on the dock instead.
	local headerFill, headerLine = CreateStrip(chatFrame, "BOTTOM")
	headerFill:SetPoint("BOTTOMLEFT", body, "TOPLEFT")
	headerFill:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT")
	headerFill:SetHeight(Theme.HEADER_HEIGHT)

	-- The footer has no line of its own: the field's edge, just under it,
	-- marks it (two lines a few pixels apart crowded the field).
	local footerFill = ns.Shapes.Fill(chatFrame, "BACKGROUND", 0, Theme.CARD_RADIUS, "BOTTOM")
	footerFill:SetColor(Theme.HEADER:GetRGBA())
	footerFill:SetPoint("TOPLEFT", body, "BOTTOMLEFT")
	footerFill:SetPoint("TOPRIGHT", body, "BOTTOMRIGHT")
	footerFill:SetHeight(Theme.FOOTER_HEIGHT)

	local shadow = CreateShadow(chatFrame, headerFill.box, footerFill.box)

	return {
		body = body,
		headerFill = headerFill,
		footerFill = footerFill,
		-- Drawn over the background: they fade out with it when the player
		-- makes the chat see-through. The header's line rests with the open
		-- tab, whose frame flows into it; the shadow goes at rest.
		headerLine = headerLine,
		overlays = { shadow },
		shadow = shadow,
		-- Regions to anchor to; the header's fills are shapes.
		top = headerFill.box,
		footer = footerFill.box,
		header = { headerFill, headerLine },
		-- Rest with the controls: the edit box's field and its hint.
		chrome = {},
		controls = {},
		-- Rest with the open tab: the combat log's filter bar, which the game
		-- hangs from the tab to share its fade.
		openTab = {},
		holds = {},
	}
end

-- The dock holds the docked tabs and is exactly the header's size and place,
-- so painting the header on it keeps the tabs (its children) on top.
local function PaintDockHeader()
	local fill, line = CreateStrip(GENERAL_CHAT_DOCK, "BOTTOM")
	fill:SetAllPoints(GENERAL_CHAT_DOCK)
	return { fill, line }
end

-- The docked windows share the header painted on the dock and the button
-- rail: they follow the window on show.
local function ApplyDockBackground()
	if not dockHeader then
		return
	end
	local shown = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) or DEFAULT_CHAT_FRAME
	local opacity = OpacityOf(shown)
	local bodyR, bodyG, bodyB, r, g, b = CardColors(shown)
	local bodyAlpha = FillAlpha(Theme.BODY.a, opacity)
	dockHeader.colors = {
		body = { bodyR, bodyG, bodyB, bodyAlpha },
		header = { r, g, b, FillAlpha(Theme.HEADER.a, opacity) },
		rest = RestLevel(bodyAlpha, opacity),
	}
	dockHeader.overlayFactor = OverlayFactor(opacity)
	ns.Buttons.SetOverlay(OverlayFactor(opacity))
	local skin = chatSkins[shown]
	if skin then
		ApplyChrome(skin, skin.lit)
	end
end

local function ApplyBackground(skin)
	local opacity = OpacityOf(skin.chatFrame)
	local bodyR, bodyG, bodyB, headerR, headerG, headerB = CardColors(skin.chatFrame)
	local bodyAlpha = FillAlpha(Theme.BODY.a, opacity)
	skin.body:SetColorTexture(bodyR, bodyG, bodyB, bodyAlpha)
	-- The strips' colors, painted by ApplyChrome as the chat fades.
	skin.colors = {
		body = { bodyR, bodyG, bodyB, bodyAlpha },
		header = { headerR, headerG, headerB, FillAlpha(Theme.HEADER.a, opacity) },
		rest = RestLevel(bodyAlpha, opacity),
	}
	skin.overlayFactor = OverlayFactor(opacity)
	ApplyChrome(skin, skin.lit)
end

local function UpdateHeaders()
	for chatFrame, skin in pairs(chatSkins) do
		for _, region in ipairs(skin.header) do
			region:SetShown(not chatFrame.isDocked)
		end
	end
end

local function SkinChatFrame(chatFrame)
	if chatSkins[chatFrame] then
		return
	end

	local name = chatFrame:GetName()
	chatFrame.Background:SetTexture(nil)
	for _, key in ipairs(BLIZZARD_BORDER_TEXTURES) do
		_G[name .. key]:SetTexture(nil)
	end
	for _, key in ipairs(BUTTON_FRAME_TEXTURES) do
		_G[name .. key]:SetTexture(nil)
	end
	-- A public ScrollingMessageFrame setter: runs as a secure barrier.
	chatFrame:SetSpacing(LINE_SPACING)

	local skin = CreatePanel(chatFrame)
	skin.chatFrame = chatFrame
	skin.driver = CreateFrame("Frame")
	skin.lit = 0
	chatSkins[chatFrame] = skin

	skin.tab = ns.Tabs.Skin(_G[name .. "Tab"], chatFrame)
	-- A floating window's own header opens under its tab, which stands at
	-- the header's left end (Tabs.AlignTab) with the open tab's look.
	local tab = _G[name .. "Tab"]
	local function UpdateOwnGap()
		OpenHeader(skin.headerFill, skin.headerLine, 0, tab:GetWidth(), nil, PixelUtil.ConvertPixelsToUIForRegion(1, tab))
	end
	skin.updateOwnGap = UpdateOwnGap
	tab:HookScript("OnSizeChanged", UpdateOwnGap)
	UpdateOwnGap()
	ns.EditBox.Skin(chatFrame, skin)
	ns.Resize.Attach(chatFrame, skin)
	ApplyBackground(skin)
	-- A hidden window's card isn't painted as the chat fades (ApplyChrome).
	chatFrame:HookScript("OnShow", function()
		ApplyChrome(skin, skin.lit)
		-- A tab opened with the mouse on the chat: no fade in comes for it.
		if chatFrame.hasBeenFaded then
			BringLinesBack(skin)
		end
		if not restAlways and not skin.holds.hover and MouseOverCard(chatFrame) then
			Skin.Hold(skin, "hover", true)
		end
	end)
	if Theme.hiddenAtRest then
		Wake(skin, false)
	elseif restAlways then
		KeepInSight(skin)
	end
end

local function SkinAllChatFrames()
	for _, name in pairs(CHAT_FRAMES) do
		SkinChatFrame(_G[name])
	end
	UpdateHeaders()
end

-- The combat log's filter bar (Blizzard_CombatLog's quick buttons: "My
-- actions", "What happened to me?"...) sits in the card as a toolbar under
-- the header: no black band and no line of its own (a third gold line like
-- the header's and the footer's read as repetition). Its buttons stay
-- Blizzard's own (white for the current filter, grey for the rest): styling
-- them from here (fonts, widths, colors) made clicking a filter fail, since
-- applying one is a protected call in Forever and the click then ran tainted
-- (the active mark never moved).
local function StyleCombatLogFilters()
	local bar = COMBATLOG and COMBATLOG.CombatLogQuickButtonFrame
	if not bar then
		return
	end
	local background = _G.CombatLogQuickButtonFrame_CustomTexture
	if background then
		background:SetColorTexture(0, 0, 0, 0)
	end
	-- The bar rests like the open tab.
	local skin = chatSkins[COMBATLOG]
	if skin then
		table.insert(skin.openTab, bar)
		ApplyChrome(skin, skin.lit)
		-- Its lines have no spacing of Everchat's (Timestamps.lua), so the
		-- frame's own callback tells when they move.
		COMBATLOG:AddOnDisplayRefreshedCallback(function()
			if Theme.hiddenAtRest then
				EdgeLines(skin, skin.edgeAlpha or 1)
			end
		end)
	end
end

-- How long new messages show on a hidden chat at rest (the options).
function Skin.SetHiddenSeconds()
	for _, skin in pairs(chatSkins) do
		if Theme.hiddenAtRest and skin.awake == false then
			skin.chatFrame:SetTimeVisible(LinesVisible())
		end
	end
end

-- Hidden at rest or not (the options): the rest levels change, so everything
-- is painted again, and the lines go back to the game's own fading.
function Skin.SetHiddenAtRest(hidden)
	hidden = hidden and true or false
	Theme.hiddenAtRest = hidden
	for _, skin in pairs(chatSkins) do
		if hidden then
			Wake(skin, skin.lit > 0)
			-- Turned on with the mouse on the chat (its side bar's eye), it
			-- stays in sight until the mouse leaves.
			if MouseOverCard(skin.chatFrame) then
				Skin.Hold(skin, "hover", true)
			end
		else
			skin.awake = nil
			if skin.revealing then
				RevealLines(skin, 1)
			end
			SetClipInset(skin, 0)
			RestoreLines(skin)
		end
	end
	Skin.WatchHover()
	if not hidden then
		for _, skin in pairs(chatSkins) do
			if skin.holds.hover then
				Skin.Hold(skin, "hover", false)
			end
		end
	end
	Theme.Set(Theme.current, Theme.minimal)
	-- The side bar's eye and the options show it, wherever it changed.
	ns.Alerts.NotifySwitchChanged()
end

-- The chat while not in use, a choice of three, in the order the side bar's
-- eye goes through them: each with its name and its words for the tooltip.
local NEXT_REST = { faded = "hidden", hidden = "always", always = "faded" }

function Skin.RestChoices()
	local L = ns.L
	return {
		{ "faded", L.restFaded, L.restFadedTip },
		{ "hidden", L.restHidden, L.restHiddenTip },
		{ "always", L.restAlways, L.restAlwaysTip },
	}
end

function Skin.NextRest(mode)
	return NEXT_REST[mode] or "hidden"
end

-- The watcher runs while the chat rests faded or hidden.
function Skin.WatchHover()
	hoverWatcher:SetScript("OnUpdate", not restAlways and WatchHover or nil)
	if restAlways then
		for _, skin in pairs(chatSkins) do
			if skin.holds.hover then
				Skin.Hold(skin, "hover", false)
			end
		end
	end
end

function Skin.SetRestMode(mode)
	ns.db.chatRest = mode
	local always = mode == "always"
	if restAlways and not always then
		restAlways = false
		for _, skin in pairs(chatSkins) do
			Skin.Hold(skin, "always", false)
			RestoreLines(skin)
		end
	end
	local hidden = mode == "hidden"
	if hidden ~= Theme.hiddenAtRest then
		Skin.SetHiddenAtRest(hidden)
	end
	if always and not restAlways then
		restAlways = true
		for _, skin in pairs(chatSkins) do
			KeepInSight(skin)
		end
	end
	Skin.WatchHover()
	ns.Alerts.NotifySwitchChanged()
end

-- The open tab's alpha in the window's fade (Header.lua puts the combat log's
-- filter bar back after a drag).
function Skin.OpenTabAlpha(chatFrame)
	local skin = chatSkins[chatFrame]
	return skin and Theme.Rest(Theme.REST_OPEN_TAB, skin.lit) or 1
end

-- The docked header's color under the mouse: the theme, the window's own
-- background color and opacity (Padlock.lua).
function Skin.DockHeaderColor()
	if dockHeader and dockHeader.colors then
		return StripColor(dockHeader.colors, 1)
	end
	return Theme.HEADER:GetRGBA()
end

-- Whether the chat is out of sight now, hidden at rest.
function Skin.IsChatHidden()
	if not Theme.hiddenAtRest then
		return false
	end
	local skin = chatSkins[FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) or DEFAULT_CHAT_FRAME]
	return not skin or skin.lit < 0.5
end

function Skin.Init()
	dockHeader = PaintDockHeader()
	SkinAllChatFrames()
	ns.Resize.Init()
	ns.Tabs.Init()
	ns.Header.Init()
	ns.Buttons.Init()

	-- New and temporary windows (whispers, pet battles...) are created later.
	hooksecurefunc("FCF_OpenNewWindow", SkinAllChatFrames)
	hooksecurefunc("FCF_OpenTemporaryWindow", SkinAllChatFrames)
	-- Docking and undocking decide which header a window uses.
	hooksecurefunc("FCF_DockUpdate", UpdateHeaders)
	-- The game's Background opacity (tab menu), and the window on show for
	-- the shared header.
	hooksecurefunc("FCF_SetWindowAlpha", function(chatFrame, alpha)
		local skin = chatFrame and chatSkins[chatFrame]
		if skin and type(alpha) == "number" then
			LookOf(chatFrame).alpha = alpha
			ApplyBackground(skin)
			ApplyDockBackground()
		end
	end)
	hooksecurefunc("FCF_SetWindowColor", function(chatFrame, r, g, b)
		local skin = chatFrame and chatSkins[chatFrame]
		if skin and type(r) == "number" and type(g) == "number" and type(b) == "number" then
			local look = LookOf(chatFrame)
			look.r, look.g, look.b = r, g, b
			ApplyBackground(skin)
			ApplyDockBackground()
		end
	end)
	hooksecurefunc("FCFDock_SelectWindow", ApplyDockBackground)
	ApplyDockBackground()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_CombatLog", StyleCombatLogFilters)
	-- A new theme: its lines, hairlines and header color everywhere.
	Theme.OnChanged(function()
		for _, trim in ipairs(themedTrims) do
			trim:Layout()
		end
		for _, hairline in ipairs(themedHairlines) do
			hairline:SetColor(Theme.HAIRLINE:GetRGBA())
		end
		for _, skin in pairs(chatSkins) do
			skin.updateOwnGap()
			ApplyBackground(skin)
		end
		Skin.SetHeaderGap(headerGap.left, headerGap.right, headerGap.limit)
		ApplyDockBackground()
	end)

	-- Lines that move keep only whole messages in sight on a hidden chat.
	ns.Timestamps.OnLinesPlaced(function(chatFrame)
		local skin = chatSkins[chatFrame]
		if skin and Theme.hiddenAtRest then
			EdgeLines(skin, skin.edgeAlpha or 1)
		end
	end)
	-- New lines keep a hidden chat's lines in sight a while (Wake).
	ns.Lines.AddListener(function(chatFrame)
		local skin = chatSkins[chatFrame]
		if skin and Theme.hiddenAtRest and not skin.awake then
			skin.linesUntil = GetTime() + LinesVisible() + LINES_FADE
		end
	end)
	if ns.db.chatRest ~= "faded" then
		Skin.SetRestMode(ns.db.chatRest)
	end
	Skin.WatchHover()

	-- Follow Blizzard's mouseover fade timing.
	hooksecurefunc("FCF_FadeInChatFrame", function(chatFrame)
		local skin = chatSkins[chatFrame]
		NoteMouse()
		if skin and not skin.holds.always then
			FadeTo(skin, 1, CHAT_FRAME_FADE_TIME)
			BringLinesBack(skin)
		end
	end)
	hooksecurefunc("FCF_FadeOutChatFrame", function(chatFrame)
		local skin = chatSkins[chatFrame]
		-- Stay lit while the player is typing or resizing.
		if skin and not next(skin.holds) then
			FadeTo(skin, 0, CHAT_FRAME_FADE_OUT_TIME)
		end
	end)
end
