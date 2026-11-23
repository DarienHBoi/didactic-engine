--------------------------------------------------------------------------------
-- The settings panel: opened from More at the end of the search bar (or /seek config, or a
-- right-click on the minimap button), in four tabs:
--   Favourites: your bar's buttons in order, and every favourite (on the bar, pinned)
--   Search: where the search bar sits, what a search looks through, recent searches
--   Options: the markers, the minimap button, the repair reminder
--   Questie: Questie kept out of the way, or as it comes
-- It sits on the map by the bar and closes with the map.
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local Settings = {}
ns.Settings = Settings

local WIDTH = 300
local PAD = 14
local INNER = WIDTH - 2 * PAD   -- the content's width
local ICON = 30
local PER_ROW = 6
local GAP = (INNER - PER_ROW * ICON) / (PER_ROW - 1)   -- (the grid spans the content's width: 12)

local panel
local controls = {}   -- each has :Refresh(), run when the panel opens and after a change

--------------------------------------------------------------------------------
-- The EllesmereUI skin, when it's installed (and its third-party skinning is on for MapSeek):
-- the panel in your EUI theme. Without it, the panel keeps its own dark look.
--------------------------------------------------------------------------------

local skin              -- EUI's skinning facade (S), once EUI hands it over
local texts, buttons, checks, closers, tabList = {}, {}, {}, {}, {}

local function Text(parent, font)
	local t = ns.Text(parent, font)
	texts[#texts + 1] = t
	return t
end

local function Skin()
	local S = skin
	if not (S and panel) or panel.skinned then return end
	panel.skinned = true
	if panel.SetBackdrop then panel:SetBackdrop(nil) end
	if panel.plainBg then panel.plainBg:Hide() end
	S.Shell(panel)
	panel.title:ClearAllPoints()
	panel.title:SetPoint("LEFT", panel, "TOPLEFT", PAD, -13)   -- (in the shell's title strip)
	panel.close:ClearAllPoints()
	panel.close:SetPoint("RIGHT", panel, "TOPRIGHT", -4, -13)
	-- (EUI's font, unless one's picked here)
	if not ns.FontPath() then for _, t in ipairs(texts) do S.Font(t) end end
	for _, b in ipairs(buttons) do S.Button(b) S.StateButtonLabel(b) end
	for _, c in ipairs(checks) do S.Checkbox(c) end
	for _, x in ipairs(closers) do S.CloseButton(x) end
	for _, b in ipairs(tabList) do S.Tab(b) end
end

ns.OnSkin(function(S)
	skin = S
	Skin()   -- (the panel is built on first open: skinned then if not now)
end)

local Fit   -- (below: the panel as tall as the tab shown)

local function RefreshAll()
	for _, c in ipairs(controls) do c:Refresh() end
	if Fit then Fit() end
end

local function Header(parent, text, y)
	local t = Text(parent, "GameFontNormal")
	t:SetPoint("TOPLEFT", PAD, y)
	t:SetText(text)
	return y - 18, t
end

local function Note(parent, text, y)
	local t = Text(parent, "GameFontDisableSmall")
	t:SetPoint("TOPLEFT", PAD, y)
	-- (a set width, not a right anchor: measured now, before the panel is placed, a note
	-- anchored right reads as one line and what comes after lands on top of it)
	t:SetWidth(INNER)
	t:SetJustifyH("LEFT")
	t:SetText(text)
	return y - (t:GetStringHeight() + 8)
end

local function CheckBox(parent, size)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(size, size)
	for _, r in ipairs({ c.text, c.Text }) do if r then r:SetText("") end end
	checks[#checks + 1] = c
	return c
end

local function Check(parent, label, tip, get, set, y)
	local c = CheckBox(parent, 24)
	c:SetPoint("TOPLEFT", PAD - 4, y)
	local t = Text(c, "GameFontHighlightSmall")
	t:SetPoint("LEFT", c, "RIGHT", 2, 0)
	t:SetText(label)
	c:SetHitRectInsets(0, -(t:GetStringWidth() + 4), 0, 0)
	c:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		RefreshAll()
	end)
	c:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(label, 1, 0.82, 0.1)
		GameTooltip:AddLine(tip, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	c:SetScript("OnLeave", function() GameTooltip:Hide() end)
	c.Refresh = function(self) self:SetChecked(get() and true or false) end
	controls[#controls + 1] = c
	return y - 24
end

local function SmallButton(parent, text, w)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w or 22, 20)
	b:SetText(text)
	buttons[#buttons + 1] = b
	return b
end

--------------------------------------------------------------------------------
-- Your bar: its buttons in order, to drag along or take off
--------------------------------------------------------------------------------

-- your bar as it is, in order: drag one to move it, click it to take it off
local function BarRow(parent, y)
	local slots = {}
	local function Row()
		local out = {}
		for _, b in ipairs(slots) do if b:IsShown() then out[#out + 1] = b end end
		return out
	end
	local empty = Text(parent, "GameFontDisableSmall")
	empty:SetPoint("TOPLEFT", PAD, y - 10)
	empty:SetText(L["No quick buttons. Pick some below."])
	for i = 1, ns.UI.MAX_BUTTONS do
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(ICON, ICON)
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.6)
		local tex = b:CreateTexture(nil, "ARTWORK")
		tex:SetPoint("TOPLEFT", 3, -3)
		tex:SetPoint("BOTTOMRIGHT", -3, 3)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b.Refresh = function(self)
			self:ClearAllPoints()
			self:SetPoint("TOPLEFT", PAD + (i - 1) * (ICON + GAP), y)
			local key = ns.UI.ShownKeys()[i]
			local spec = key and ns.UI.Spec(key)
			self.key, self.spec = key, spec
			if spec then
				ns.SetLook(tex, ns.LOOKS[spec.icon])
				self:Show()
			else
				self:Hide()
			end
			if i == 1 then empty:SetShown(not spec) end
		end
		b:SetScript("OnClick", function(self)
			if ns.UI.JustDropped(self) or not self.key then return end
			for at, k in ipairs(ns.db.buttons) do
				if k == self.key then table.remove(ns.db.buttons, at) break end
			end
			ns.UI.Layout()
			ns.UI.Place()
			RefreshAll()
		end)
		b:SetScript("OnEnter", function(self)
			if not self.spec then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.spec.label, 1, 0.82, 0.1)
			GameTooltip:AddLine(L["Drag to move it along the bar"], 1, 1, 1)
			GameTooltip:AddLine(L["Click to take it off"], 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		ns.UI.Draggable(b, Row, function(self, to)
			if self.key then ns.UI.MoveButton(self.key, to) else RefreshAll() end
		end)
		slots[i] = b
		controls[#controls + 1] = b
	end
	return y - (ICON + 10)
end

--------------------------------------------------------------------------------
-- Pulse length: - n +
--------------------------------------------------------------------------------

-- a number setting: its label (text(n)), and - and + buttons stepping it by step within lo..hi
-- (lines: the label's lines at most, room kept for them; it stays clear of the buttons)
local function Stepper(parent, y, key, lo, hi, step, text, tip, lines)
	lines = lines or 1
	local h = lines == 1 and 22 or lines * 13 + 6
	local label = Text(parent, "GameFontHighlightSmall")
	label:SetPoint("LEFT", parent, "TOPLEFT", PAD, y - h / 2)
	label:SetWidth(INNER - 52)
	label:SetJustifyH("LEFT")
	local minus = SmallButton(parent, "-")
	local plus = SmallButton(parent, "+")
	plus:SetPoint("RIGHT", parent, "TOPRIGHT", -PAD, y - h / 2)
	minus:SetPoint("RIGHT", plus, "LEFT", -2, 0)
	local function Step(d)
		ns.db[key] = math.max(lo, math.min(hi, (ns.db[key] or lo) + d * step))
		RefreshAll()
	end
	minus:SetScript("OnClick", function() Step(-1) end)
	plus:SetScript("OnClick", function() Step(1) end)
	if tip then
		for _, b in ipairs({ minus, plus }) do
			b:HookScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(tip, 1, 1, 1, true)
				GameTooltip:Show()
			end)
			b:HookScript("OnLeave", function() GameTooltip:Hide() end)
		end
	end
	controls[#controls + 1] = { Refresh = function()
		local n = ns.db[key]
		label:SetText(text(n))
		minus:SetEnabled(n > lo)
		plus:SetEnabled(n < hi)
	end }
	return y - h - 4
end

-- a setting picked from a menu: a row with its label (text(the picked one's name)) and a button
-- that opens the menu of choices (items() = ns.OpenMenu's items, worked out each time).
-- Without a menu of the game's, a click goes to the next choice
local function Chooser(parent, y, name, items, text, tip, room)
	local h = 22
	local row = CreateFrame("Button", nil, parent)
	row:SetPoint("TOPLEFT", PAD, y)
	row:SetSize(INNER, h)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	local label = Text(row, "GameFontHighlightSmall")
	label:SetPoint("LEFT", 0, 0)
	label:SetPoint("RIGHT", -(28 + (room or 0)), 0)   -- (room: for a button beside it)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	local open = SmallButton(parent, "v")
	open:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	local arrow = open:CreateTexture(nil, "OVERLAY")
	arrow:SetSize(14, 14)
	arrow:SetPoint("CENTER", 0, -1)
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetRotation(-math.pi / 2)
	open:SetText("")
	local function Open(self)
		GameTooltip:Hide()
		local list = items()
		if ns.OpenMenu(self, list) then return end
		-- (no menu: the next choice)
		local radios = {}
		for _, it in ipairs(list) do if it.radio then radios[#radios + 1] = it end end
		local at = 1
		for i, it in ipairs(radios) do if it.checked() then at = i end end
		local nxt = radios[at % #radios + 1]
		if nxt then nxt.func() end
		RefreshAll()
	end
	row:SetScript("OnClick", Open)
	open:SetScript("OnClick", Open)
	if tip then
		for _, b in ipairs({ row, open }) do
			b:HookScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(tip, 1, 1, 1, true)
				GameTooltip:Show()
			end)
			b:HookScript("OnLeave", function() GameTooltip:Hide() end)
		end
	end
	controls[#controls + 1] = { Refresh = function() label:SetText(text(name())) end }
	return y - h - 4
end

local function Seconds(n) return (n == 1 and L["|cffffffff%d|r second"] or L["|cffffffff%d|r seconds"]):format(n) end

--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Favourites: the quick searches and searches you starred, each with its icon on the bar (a
-- typed search's: click to change), on the bar or not, pinned or not, the one the minimap button
-- finds, and a cross to take its star off. Under them, more quick searches to star
--------------------------------------------------------------------------------

local function Favourites(parent, y)
	local empty = Text(parent, "GameFontDisableSmall")
	empty:SetPoint("TOPLEFT", PAD, y - 24)
	empty:SetWidth(INNER)
	empty:SetJustifyH("LEFT")
	empty:SetText(L["No favourites yet. Search, open the star at the end of the search box, and star it."])
	local h1 = Text(parent, "GameFontDisableSmall")
	h1:SetText(L["Bar"])
	local h2 = Text(parent, "GameFontDisableSmall")
	h2:SetText(L["Pin"])
	local h3 = Text(parent, "GameFontDisableSmall")
	h3:SetText(L["Minimap"])
	y = y - 14
	local ROWH = 22
	local add = SmallButton(parent, L["+ Add a quick search"], 150)
	for i = 1, ns.UI.FAVORITES_MAX do
		local top = y - (i - 1) * ROWH
		local icon = CreateFrame("Button", nil, parent)
		icon:SetSize(18, 18)
		icon:SetPoint("TOPLEFT", PAD, top - 2)
		icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local tex = icon:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		local label = Text(parent, "GameFontHighlightSmall")
		label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(false)
		-- (the X at the right edge, the Pin and Bar boxes left of it, each centred on its column)
		local x = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
		x:SetSize(20, 20)
		x:SetPoint("RIGHT", parent, "TOPRIGHT", -PAD + 3, top - ROWH / 2)
		closers[#closers + 1] = x
		local pin = CheckBox(parent, 22)
		pin:SetPoint("RIGHT", x, "LEFT", -4, 0)
		local onBar = CheckBox(parent, 22)
		onBar:SetPoint("RIGHT", pin, "LEFT", -4, 0)
		local onMini = CheckBox(parent, 22)
		onMini:SetPoint("RIGHT", onBar, "LEFT", -4, 0)
		label:SetPoint("RIGHT", onMini, "LEFT", -6, 0)
		if i == 1 then
			h1:SetPoint("BOTTOM", onBar, "TOP", 0, 1)
			h2:SetPoint("BOTTOM", pin, "TOP", 0, 1)
			h3:SetPoint("BOTTOM", onMini, "TOP", 0, 1)
		end

		local row = {}
		row.Refresh = function()
			local q = ns.db.favorites[i]
			local spec = q and ns.UI.FavSpec(q)
			row.q, row.spec = q, spec
			for _, w in ipairs({ icon, label, onBar, pin, onMini, x }) do w:SetShown(spec ~= nil) end
			if i == 1 then
				empty:SetShown(q == nil)
				h1:SetShown(q ~= nil) h2:SetShown(q ~= nil) h3:SetShown(q ~= nil)
			end
			if not spec then return end
			label:SetText(ns.UI.IsQuick(q) and spec.label or q)
			ns.SetLook(tex, ns.LOOKS[spec.icon] or ns.LOOKS.SEARCH)
			local on = ns.UI.OnBar(q)
			tex:SetDesaturated(not on)
			tex:SetAlpha(on and 1 or 0.5)
			onBar:SetChecked(on)
			pin:SetChecked(ns.db.pinned == q)
			local onM = ns.UI.OnMini(q)
			onMini:SetChecked(onM)
			onMini:SetEnabled(onM or #ns.db.minimapButtons < ns.UI.MINI_MAX)
		end
		icon:SetScript("OnClick", function(self, button)
			if not row.q or ns.UI.IsQuick(row.q) then return end
			GameTooltip:Hide()
			if button == "RightButton" or not ns.UI.IconMenu(self, row.q) then
				ns.UI.CycleIcon(row.q, button == "RightButton")
			end
		end)
		icon:SetScript("OnEnter", function(self)
			if not row.q then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if ns.UI.IsQuick(row.q) then
				GameTooltip:AddLine(row.spec.label, 1, 0.82, 0.1)
				GameTooltip:AddLine(L["A quick search: its icon is its own."], 1, 1, 1, true)
			else
				GameTooltip:AddLine(L["Its button's icon"], 1, 0.82, 0.1)
				GameTooltip:AddLine(L["Click to pick one."], 1, 1, 1, true)
			end
			GameTooltip:Show()
		end)
		onBar:SetScript("OnClick", function()
			if row.q then ns.UI.ToggleOnBar(row.q) end
			RefreshAll()
		end)
		onBar:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(L["On the bar"], 1, 0.82, 0.1)
			GameTooltip:AddLine(L["A button of its own on the map's bar (under More once the bar has 5). Drag it along in the Bar tab."], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		pin:SetScript("OnClick", function()
			if row.q then ns.UI.TogglePin(row.q) end
			RefreshAll()
		end)
		onMini:SetScript("OnClick", function()
			if row.q then ns.UI.ToggleMini(row.q) end
			RefreshAll()
		end)
		onMini:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(L["On the minimap button"], 1, 0.82, 0.1)
			GameTooltip:AddLine(L["One of the quick searches a click on the minimap button offers (up to 6). A click on one finds it on the minimap without opening the map; a click again clears it."], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		pin:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(L["Pinned"], 1, 0.82, 0.1)
			GameTooltip:AddLine(L["It stays on the map and minimap after you close the map, until you unpin it. One at a time."], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		x:SetScript("OnClick", function()
			if row.q then ns.UI.ToggleFavorite(row.q) end
			RefreshAll()
		end)
		x:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(L["Take the star off"], 1, 0.82, 0.1)
			GameTooltip:AddLine(L["Off the bar too. A pin stays until you unpin it."], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		for _, w in ipairs({ icon, onBar, pin, x }) do w:HookScript("OnLeave", function() GameTooltip:Hide() end) end
		controls[#controls + 1] = row
	end
	-- the quick searches not starred yet, to star
	add:SetScript("OnClick", function(self)
		local items = {}
		for _, spec in ipairs(ns.UI.Catalog()) do
			if not ns.UI.IsFavorite(spec.query) then
				items[#items + 1] = { text = spec.label, look = ns.LOOKS[spec.icon], func = function()
					ns.UI.Star(spec.query)
					RefreshAll()
				end }
			end
		end
		ns.OpenMenu(self, items)
	end)
	add:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Star one of the quick searches (Repair, Vendor, Your group ...)."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	add:SetScript("OnLeave", function() GameTooltip:Hide() end)
	controls[#controls + 1] = { Refresh = function()
		local left = false
		for _, spec in ipairs(ns.UI.Catalog()) do if not ns.UI.IsFavorite(spec.query) then left = true end end
		add:SetEnabled(left and #ns.db.favorites < ns.UI.FAVORITES_MAX)
		-- (under the last one)
		local n = math.min(#ns.db.favorites, ns.UI.FAVORITES_MAX)
		add:ClearAllPoints()
		add:SetPoint("TOPLEFT", PAD, y - n * ROWH - (n == 0 and 40 or 4))
	end }
	-- (the page as tall as the list: its rows, the add button)
	return function()
		local n = math.min(#ns.db.favorites, ns.UI.FAVORITES_MAX)
		return -y + n * ROWH + (n == 0 and 40 or 4) + 26
	end
end

--------------------------------------------------------------------------------
-- The panel: its tabs (Favourites, Search, Options, Questie)
--------------------------------------------------------------------------------

local TABS = { { key = "favs", label = L["Favourites"] }, { key = "search", label = L["Search"] }, { key = "options", label = L["Options"] },
	{ key = "questie", label = L["Questie"] } }
-- (no Questie: nothing of Questie's to set)
if not _G.Questie then TABS[#TABS] = nil end
local TOP = 64   -- the title and the tabs
local pages, tabs, shownTab = {}, {}, "favs"

local function Page(f)
	local p = CreateFrame("Frame", nil, f)
	p:SetPoint("TOPLEFT", 0, -TOP)
	p:SetPoint("TOPRIGHT", 0, -TOP)
	p:SetHeight(1)
	p:Hide()
	return p
end

local function PageHeight(p)
	return type(p.height) == "function" and p.height() or p.height
end

function Fit()
	if panel and pages[shownTab] then panel:SetHeight(TOP + PageHeight(pages[shownTab]) + 6) end
end

local function ShowTab(key)
	shownTab = key
	for _, t in ipairs(TABS) do
		pages[t.key]:SetShown(t.key == key)
		local tab = tabs[t.key]
		if panel.skinned and skin.SetTabSelection then
			tab:SetEnabled(true)   -- (EUI's tab look shows which: its accent underline)
			skin.SetTabSelection(tab, t.key == key)
		else
			tab:SetEnabled(t.key ~= key)
		end
	end
	RefreshAll()
end

local function Build()
	local ok, f = pcall(CreateFrame, "Frame", "MapSeekSettings", WorldMapFrame, "BackdropTemplate")
	if not ok or not f then f = CreateFrame("Frame", "MapSeekSettings", WorldMapFrame) end
	f:SetWidth(WIDTH)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		f:SetBackdropColor(0, 0, 0, 0.95)
	else
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.92)
		f.plainBg = bg
	end

	local title = Text(f, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -12)
	title:SetText("MapSeek")
	f.title = title
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	f.close = close
	closers[#closers + 1] = close

	local tw = (INNER - (#TABS - 1) * 4) / #TABS
	for i, t in ipairs(TABS) do
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(tw, 20)
		b:SetText(t.label)
		b:SetPoint("TOPLEFT", PAD + (i - 1) * (tw + 4), -36)
		b:SetScript("OnClick", function() ShowTab(t.key) end)
		tabs[t.key] = b
		tabList[#tabList + 1] = b
	end

	local db = ns.db

	-- Favourites: your bar (its order), and every favourite, each on the bar or not, pinned or not
	local p = Page(f)
	pages.favs = p
	local y = -4
	local count
	y, count = Header(p, L["Your bar"], y)
	local barCount = Text(p, "GameFontDisableSmall")
	barCount:SetPoint("BOTTOMRIGHT", p, "TOPRIGHT", -PAD, y + 4)   -- (on the header's line)
	controls[#controls + 1] = { Refresh = function()
		local n = #ns.UI.PickedKeys()
		local extra = math.max(0, n - ns.UI.MAX_BUTTONS)
		barCount:SetText(extra > 0 and L["%d on the bar, %d under More"]:format(n - extra, extra)
			or L["%d of %d on the bar"]:format(n, ns.UI.MAX_BUTTONS))
	end }
	y = Note(p, L["Drag to reorder (on the map's bar too). Click one to take it off. Tick Bar on more favourites below; past 5 they go under More."], y)
	y = BarRow(p, y)
	y = Header(p, L["Favourites"], y)
	y = Note(p, L["Your quick searches and the searches you starred (the star at the end of the search box). Put one on the bar, or pin one to keep it on the map and minimap."], y)
	p.height = Favourites(p, y - 4)

	-- Search: the bar's place, what a search looks through, recent searches
	p = Page(f)
	pages.search = p
	y = -4
	y = Header(p, L["Search bar"], y)
	-- where the bar sits: top, bottom or anywhere (move mode), and the button for move mode
	local POS = { top = L["Top"], bottom = L["Bottom"], custom = L["Custom"] }
	local function PosItems()
		local items = {}
		for _, k in ipairs({ "top", "bottom", "custom" }) do
			items[#items + 1] = { text = POS[k], radio = true,
				checked = function() return (db.barPos or "top") == k end,
				func = function() ns.UI.SetBarPos(k) RefreshAll() end }
		end
		return items
	end
	local moveBtn = SmallButton(p, L["Move it"], 70)
	y = Chooser(p, y, function() return POS[db.barPos or "top"] end, PosItems, function(name)
		return L["Search bar: %s"]:format("|cffffffff" .. name .. "|r")
	end, L["Where the search bar sits on the map: across the top (over the breadcrumbs), along the bottom, or anywhere you drag it (Custom). Move it: drag it where you like while the map's open."], 74)
	moveBtn:SetPoint("RIGHT", p, "TOPRIGHT", -PAD - 26, y + 15)
	moveBtn:SetScript("OnClick", function()
		ns.UI.MoveMode()
		RefreshAll()
	end)
	moveBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Move it"], 1, 0.82, 0.1)
		GameTooltip:AddLine(L["Drag the search bar anywhere on the map, then right-click it (or click Done here)."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	moveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	controls[#controls + 1] = { Refresh = function()
		moveBtn:SetText(ns.UI.Moving() and L["Done"] or L["Move it"])
	end }
	y = Check(p, L["Open the search with the map"],
		L["The search box is open whenever the map opens, over the breadcrumbs. Click the search button (the spyglass) to hide it and use the breadcrumbs. Off: the search opens only from the search button."],
		function() return db.searchOpen end, function(v) ns.UI.SetSearchOpen(v) end, y)
	y = y - 6

	y = Header(p, L["Results"], y)
	y = Check(p, L["Move the map to the results"],
		L["When every match is in one zone, the map goes to that zone. When they're spread out and none are on the map you're looking at, it goes to the nearest one's zone."],
		function() return db.focus end, function(v) db.focus = v end, y)
	y = Check(p, L["Only the zone the map shows"],
		L["Search only the zone (or continent) the map is showing. The markers follow as you move the map."],
		function() return db.zoneOnly end, function(v) db.zoneOnly = v ns.UI.Again() end, y)
	y = Check(p, L["Trainers: only your class's"],
		L["A Trainer search leaves out other classes' trainers. Searching \"mage trainer\" still finds them."],
		function() return db.ownClass end, function(v) db.ownClass = v ns.UI.Again() end, y)
	y = Check(p, L["Trainers: only your professions"],
		L["Once you have both main professions, a Trainer search leaves out the other main professions' trainers. Cooking, fishing, first aid and riding always show, and searching one by name still finds it."],
		function() return db.ownProfs end, function(v) db.ownProfs = v ns.UI.Again() end, y)
	y = Check(p, L["Include the other faction's NPCs"], L["Show NPCs that are only friendly to the other faction."],
		function() return db.otherFaction end, function(v) db.otherFaction = v ns.Suggest.Reset() ns.UI.Again() end, y)
	y = y - 6

	y = Header(p, L["Recent searches"], y)
	y = Check(p, L["Remember recent searches"],
		L["Open the empty search box to see them. Click the X on one to remove it. Favourites are kept either way."],
		function() return db.recent end, function(v) db.recent = v end, y)
	y = Stepper(p, y, "recentMax", 1, ns.UI.RECENT_MAX, 1, function(n)
		return (n == 1 and L["Show up to |cffffffff%d|r recent search"] or L["Show up to |cffffffff%d|r recent searches"]):format(n)
	end, L["How many recent searches the empty search box lists, under your favourites."])
	local wipeBtn = SmallButton(p, L["Clear recent searches"], 150)
	wipeBtn:SetPoint("TOPLEFT", PAD, y - 2)
	wipeBtn:SetScript("OnClick", function()
		ns.UI.ClearHistory()
		ns.Print(L["recent searches cleared"])
		RefreshAll()
	end)
	controls[#controls + 1] = { Refresh = function() wipeBtn:SetEnabled(#db.history > 0) end }
	y = y - 30
	p.height = -y

	-- Options: the markers, the minimap button, the repair reminder
	p = Page(f)
	pages.options = p
	y = -4
	y = Header(p, L["Markers"], y)
	y = Stepper(p, y, "flash", 1, 60, 1, function(n) return L["Markers pulse for %s"]:format(Seconds(n)) end)
	y = Stepper(p, y, "linger", 0, 300, 5, function(n)
		return n == 0 and L["Quick buttons: off when the map closes"]
			or L["Quick buttons stay on for %s after the map closes"]:format(Seconds(n))
	end, L["A quick button's markers stay on the map and minimap this long after you close the map, then clear. 0 clears them with the map. Right-click a quick button to pin it instead."], 2)
	y = Check(p, L["Keep markers after the pulse"], L["Markers stay as steady icons until you clear the search."],
		function() return db.keep end, function(v) db.keep = v end, y)
	y = Check(p, L["Show matches on the minimap"], L["Matches in the zone you're in also go on the minimap."],
		function() return db.minimap end, function(v) db.minimap = v end, y)
	y = Check(p, L["Show routes on the minimap"], L["A route's line, and a farming loop's, are drawn on the minimap as well as the world map."],
		function() return db.miniRoute ~= false end, function(v)
			db.miniRoute = v
			if ns.Route and ns.Route.UpdateMini then ns.Route.UpdateMini() end
		end, y)
	y = Check(p, L["Farming: hide a marker where the game's dot shows"],
		L["Experimental. With Find Minerals or Find Herbs on, MapSeek looks for the game's own yellow dot at each farming marker on the minimap and hides the marker only where there is one. When off, markers hide whenever you're near."],
		function() return db.dots end, function(v) db.dots = v end, y)
	y = Check(p, L["Closing the map clears the markers"],
		L["When off, closing the map only empties the search box; the markers stay until you clear them. A pinned search always stays."],
		function() return db.closeClears ~= "list" end, function(v) db.closeClears = v and "all" or "list" end, y)
	y = y - 6

	y = Header(p, L["Minimap button"], y)
	local SIDES = { left = L["Left"], right = L["Right"], down = L["Down"], up = L["Up"] }
	local function SideItems()
		local items = {}
		for _, k in ipairs({ "left", "right", "down", "up" }) do
			items[#items + 1] = { text = SIDES[k], radio = true,
				checked = function() return (db.minimapSide or "left") == k end,
				func = function() db.minimapSide = k RefreshAll() end }
		end
		return items
	end
	y = Check(p, L["Show the minimap button"],
		L["A MapSeek button on the minimap. Click it for your quick searches (the Minimap column of the Favourites tab picks them, up to 6); Shift-click opens the map with the search box ready; right-click for these settings."],
		function() return not db.minimapIcon.hide end, function(v) ns.SetMinimapButton(v) end, y)
	y = Chooser(p, y, function() return SIDES[db.minimapSide or "left"] end, SideItems, function(name)
		return L["Its quick searches open: %s"]:format("|cffffffff" .. name .. "|r")
	end, L["Which way the quick searches open from the minimap button: a row to its left or right, or a column down or up."])
	local function FontItems()
		local items = { { text = L["The game's own"], radio = true,
			checked = function() return (db.font or "") == "" end,
			func = function() db.font = "" ns.ApplyFonts() RefreshAll() end } }
		for _, name in ipairs(ns.FontList()) do
			items[#items + 1] = { text = name, radio = true,
				checked = function() return db.font == name end,
				func = function() db.font = name ns.ApplyFonts() RefreshAll() end }
		end
		return items
	end
	y = Chooser(p, y, function() return ns.FontPath() and db.font or L["The game's own"] end, FontItems, function(name)
		return L["Font: %s"]:format("|cffffffff" .. name .. "|r")
	end, L["The font MapSeek's texts use: the game's own, or one an addon shares (Numen from FojjiCore, say: those LibSharedMedia lists)."])
	y = Check(p, L["Remind me to repair"],
		L["When your gear drops to 20% durability, offer to find the nearest repair (once you're out of combat)."],
		function() return db.repairAlert end, function(v) db.repairAlert = v end, y)
	y = y - 4
	p.height = -y

	-- Questie, which MapSeek's data comes from: kept out of the way, or as it comes
	p = Page(f)
	pages.questie = p
	y = -4
	y = Header(p, L["Questie"], y)
	y = Note(p, L["MapSeek needs Questie for its data. If you don't use Questie itself, this turns off its quest tracker, its objective icons and its chat messages, and shows the game's own quest objectives on the map. Either button reloads your UI."], y)
	local quietBtn = SmallButton(p, L["Keep Questie out of the way"], 200)
	quietBtn:SetPoint("TOPLEFT", PAD, y - 2)
	quietBtn:SetScript("OnClick", function()
		if ns.QuestieQuiet(true) then ReloadUI() else ns.Print(L["Questie isn't ready yet. Try again in a moment."]) end
	end)
	local loudBtn = SmallButton(p, L["Questie's own defaults"], 200)
	loudBtn:SetPoint("TOPLEFT", quietBtn, "BOTTOMLEFT", 0, -6)
	loudBtn:SetScript("OnClick", function()
		if ns.QuestieQuiet(false) then ReloadUI() else ns.Print(L["Questie isn't ready yet. Try again in a moment."]) end
	end)
	controls[#controls + 1] = { Refresh = function() quietBtn:SetEnabled(not ns.QuestieIsQuiet()) end }
	y = y - 56
	p.height = -y

	f:SetScript("OnShow", RefreshAll)
	f:Hide()
	return f
end

local function Anchor()
	panel:ClearAllPoints()
	local bar = ns.UI.Bar()
	if bar and bar:IsVisible() and ns.UI.Up() then
		panel:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 20)   -- (the bar's low on the map: above it)
	elseif bar and bar:IsVisible() then
		panel:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -20)
	else
		panel:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -12, -70)
	end
end

--- the panel brought up to date (the bar changed under it)
function Settings.Refresh()
	if panel and panel:IsShown() then RefreshAll() end
end

function Settings.Toggle()
	if not WorldMapFrame then return end
	if not WorldMapFrame:IsShown() then
		if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
		if panel and panel:IsShown() then return end
	end
	if not panel then panel = Build() Skin() end
	if panel:IsShown() then panel:Hide() return end
	Anchor()
	panel:Show()
	ShowTab(shownTab)
end

--- the settings open at a tab ("bar", "favs" or "options")
function Settings.Open(tab)
	if not WorldMapFrame then return end
	if not WorldMapFrame:IsShown() then
		if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
	end
	if not panel then panel = Build() Skin() end
	Anchor()
	panel:Show()
	ShowTab(tab or shownTab)
end
