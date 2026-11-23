--------------------------------------------------------------------------------
-- The search, at the right end of the map's top bar (WorldMapFrame.NavBar): a search button,
-- the quick buttons you picked (5 at most; the rest go under More), a "go to the nearest"
-- button, and More (the other quick buttons, and the settings).
-- The search button opens a search box across the top bar, over the World > Continent > Zone
-- breadcrumbs, and it closes again once you're done. Type (or press a quick button) and the
-- matches flash on the map; press the lit button again to clear. As you type, suggestions drop
-- down under the box (pick with the mouse, the arrow keys, Tab or Enter); open the empty box
-- for your recent and starred searches. A starred search can be pinned: it stays on the map
-- and minimap after the map closes, until you unpin it. A search that finds nothing tries
-- again with its spelling fixed. Drag the quick buttons to reorder them. A short count shows
-- under the bar, then fades. Closing the map clears (all but a pinned search).
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

-- money, short: "12g", "3.5g", "40s"
local function Coins(c)
	local g = c / 10000
	if g >= 10 then return ("%dg"):format(g) end
	if g >= 1 then return ("%.1fg"):format(g) end
	return ("%ds"):format(math.max(1, math.floor(c / 100)))
end

-- the kinds of farming, as a row says them
local FARM_HOW = { mine = L["Mining"], herb = L["Herbalism"], skin = L["Skinning"], mobs = L["Mob grind"] }

--- the search box's text as plain words: an item's link in it ("[Copper Ore]", shift-clicked in,
--- or put there for a farm) is its name
local function Plain(text)
	if type(text) ~= "string" or not text:find("|", 1, true) then return text end
	-- (a colour as eight hex digits, or by name: "|cnIQ1:")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|r", "")
	return (text:gsub("[%[%]]", ""))
end

-- an item's name, link and quality, by whichever call this game has; nil till the game has it
local function ItemInfo(id)
	local f = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if not (f and id) then return end
	local ok, name, link, quality = pcall(f, id)
	if ok then return name, link, quality end
end
local UI = {}
ns.UI = UI

local LIST_WIDTH = 250
local LIST_WIDEST = 560   -- (as wide as its longest row needs, a farm's with its zone, lap and gold: up to this)
local BUTTON = 24
local LIVE_DELAY = 0.35     -- seconds after the last keystroke before searching
local LIVE_MIN = 3          -- letters before searching as you type (Enter searches from 2)
local STATUS_HOLD = 4       -- seconds the count shows before fading
local RECENT_MAX = 10       -- recent searches kept (the settings pick how many show, 3 to start)
UI.RECENT_MAX = RECENT_MAX
local ROW = 20              -- height of a row in the drop-down
local FIX_BELOW = 3         -- fewer suggestions than this: offer a spelling fix too

-- every quick button there is (pick yours in the settings): key, tooltip, search, icon (a look
-- in Pins.lua, the same icon its markers get), hunter = only offered to hunters
local CATALOG = {
	{ key = "repair", label = L["Repair"], query = "repair", icon = "REPAIR" },
	{ key = "inn", label = L["Innkeeper"], query = "inn", icon = "INNKEEPER" },
	{ key = "trainer", label = L["Trainer"], query = "trainer", icon = "PROFESSION" },
	{ key = "flight", label = L["Flight master"], query = "flight", icon = "FLIGHT_MASTER" },
	{ key = "bank", label = L["Banker"], query = "bank", icon = "BANKER" },
	{ key = "ah", label = L["Auctioneer"], query = "ah", icon = "AUCTIONEER" },
	{ key = "vendor", label = L["Vendor"], query = "vendor", icon = "VENDOR" },
	{ key = "stable", label = L["Stable master"], query = "stable", icon = "STABLEMASTER", hunter = true },
	{ key = "battlemaster", label = L["Battlemaster"], query = "battlemaster", icon = "BATTLEMASTER" },
	{ key = "tabard", label = L["Tabard designer"], query = "tabard", icon = "TABARD_DESIGNER" },
	{ key = "quests", label = L["Quests for you"], query = "quests", icon = "QUEST" },
	{ key = "mailbox", label = L["Mailbox"], query = "mailbox", icon = "MAILBOX" },
	{ key = "forge", label = L["Forge"], query = "forge", icon = "FORGE" },
	{ key = "anvil", label = L["Anvil"], query = "anvil", icon = "ANVIL" },
	{ key = "campfire", label = L["Cooking fire"], query = "campfire", icon = "COOKING" },
	{ key = "stone", label = L["Meeting stone"], query = "meeting stone", icon = "MEETING_STONE" },
	{ key = "group", label = L["Your group"], query = "group", icon = "GROUP" },
}
UI.MAX_BUTTONS = 5          -- on the bar; the rest you pick go under More

local byKey, byQuery = {}, {}
for _, spec in ipairs(CATALOG) do byKey[spec.key], byQuery[spec.query] = spec, spec end
UI.ByKey = byKey

-- the icons a favourite's button can have (Settings: click its icon to change it)
UI.ICONS = { "SEARCH", "VENDOR", "REPAIR", "INNKEEPER", "FLIGHT_MASTER", "BANKER", "AUCTIONEER", "CLASS",
	"PROFESSION", "STABLEMASTER", "BATTLEMASTER", "TABARD_DESIGNER", "QUEST", "MAILBOX", "FORGE", "ANVIL",
	"COOKING", "MEETING_STONE", "GROUP" }
local FAV = "fav:"   -- a quick button that's a favourite search: "fav:" .. its search

--- a quick button: one of the catalog's, or a favourite search you put on the bar
function UI.Spec(key)
	local spec = byKey[key]
	if spec then return spec end
	local q = type(key) == "string" and key:sub(1, #FAV) == FAV and key:sub(#FAV + 1)
	if not q or q == "" then return end
	return { key = key, query = q, label = '"' .. q .. '"', fav = true,
		icon = (ns.db.favIcons and ns.db.favIcons[q]) or "SEARCH" }
end

--- a favourite's quick button key: a quick search's own ("repair"), or "fav:" .. its search
function UI.FavKey(query)
	local spec = byQuery[query]
	return spec and spec.key or FAV .. query
end

--- a favourite's quick button (its name and icon: a quick search's own, or the search's)
function UI.FavSpec(query) return UI.Spec(UI.FavKey(query)) end

--- is this favourite one of the quick searches (its icon is its own)?
function UI.IsQuick(query) return byQuery[query] ~= nil end

--- favourites and quick buttons as one list, once: the quick buttons on your bar starred (in
--- their order), then the searches you'd starred. A new install starts with a few more starred
function UI.MergeFavorites(fresh)
	local db = ns.db
	if db.favMerged then return end
	db.favMerged = true
	local out, seen = {}, {}
	local function Add(q)
		if q and q ~= "" and not seen[q] then seen[q] = true out[#out + 1] = q end
	end
	for _, key in ipairs(db.buttons) do
		local spec = UI.Spec(key)
		if spec then Add(spec.query) end
	end
	if fresh then
		for _, key in ipairs({ "vendor", "flight", "mailbox" }) do Add(byKey[key].query) end
	end
	for _, q in ipairs(db.favorites) do Add(q) end
	db.favorites = out
end

local function IsHunter() return select(2, UnitClass("player")) == "HUNTER" end

-- the buttons this character can pick from
function UI.Catalog()
	local hunter = IsHunter()
	local out = {}
	for _, spec in ipairs(CATALOG) do
		if hunter or not spec.hunter then out[#out + 1] = spec end
	end
	return out
end

local bar, edit, status, statusBox, near, liveTimer, statusTimer
local Hang   -- (the status and the list placed under the box; below)

-- the look, the same everywhere: the dark panels with a thin gold edge, gold for the numbers
local PANEL_BG = { 0.05, 0.05, 0.06, 0.94 }
local PANEL_EDGE = { 1, 0.82, 0.1, 0.45 }
local GOLD = "ffd100"
local FLAT = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

-- a flat dark panel with a thin gold edge (the list, the menus); EUI's own panel in its place
local function Flat(f)
	if f.SetBackdrop then
		f:SetBackdrop(FLAT)
		f:SetBackdropColor(unpack(PANEL_BG))
		f:SetBackdropBorderColor(unpack(PANEL_EDGE))
	else
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(unpack(PANEL_BG))
		f.plainBg = bg
	end
	ns.SkinPanel(f)
end

-- the count's words dressed: its numbers gold, its parts set off with a dot ("12 found · 12 spots · nearest 340 yd")
local function Pretty(text)
	text = text:gsub("%d+", "|cff" .. GOLD .. "%0|r")
	text = text:gsub(" %- ", " · "):gsub(", ", " · ")
	return text
end

-- what a row of the list is, by its icon
local ICONS = {
	item = { "Interface\\Icons\\INV_Misc_Bag_10", true }, npc = { "Interface\\GossipFrame\\GossipGossipIcon" },
	title = { "Interface\\GossipFrame\\TrainerGossipIcon" }, search = { "Interface\\Icons\\INV_Misc_Spyglass_03", true },
	zone = { "Interface\\Icons\\INV_Misc_Map_01", true }, city = { "Interface\\Icons\\INV_Misc_Map_01", true },
	continent = { "Interface\\Icons\\INV_Misc_Map_01", true }, town = { "Interface\\Icons\\INV_Misc_Map_01", true },
	dungeon = { "Interface\\Icons\\INV_Misc_Key_03", true }, quest = { "Interface\\GossipFrame\\AvailableQuestIcon" },
	recent = { "Interface\\Icons\\INV_Misc_PocketWatch_01", true }, pinned = { "Interface\\Icons\\INV_Misc_Map_01", true },
	fix = { "Interface\\RaidFrame\\ReadyCheck-Ready" }, manage = { "Interface\\Icons\\Trade_Engineering", true },
	fav = { "Interface\\Common\\ReputationStar", { 0, 0.5, 0, 0.5 } }, addfav = { "Interface\\Common\\ReputationStar", { 0, 0.5, 0, 0.5 } },
	ore = { "Interface\\Icons\\Trade_Mining", true }, herb = { "Interface\\Icons\\Trade_Herbalism", true },
}
local searchBtn, strip      -- the search button, and the search box's strip across the top bar
local STOP_ICON = "Interface\\Buttons\\UI-StopButton"   -- (the X over it while a search is on the map)
local more, menu            -- the More button, and its menu
local quick = {}              -- the button frames, reused as the picks change
local shown = {}              -- the ones on the bar now, in order
local pending                 -- a query typed before the index was ready
local lit                     -- the query of the quick button lit now
local lastTyped               -- the last typed search that found something (kept when you're done)
local previewing              -- the map shows a row of the list looked at, not what's in the box
local lookedAt                -- (that row's search)
local lingerTimer             -- clears a quick button's search a while after the map closes
local current                 -- the search on the map now (shown again when the map changes, zone-only)
local list, rows = nil, {}    -- the drop-down under the box: recent searches, or suggestions
local listData = {}           -- what its rows show: { text, hint, kind = "recent" | "suggest" | "fix" }
local sel                     -- the row picked with the arrow keys

--------------------------------------------------------------------------------
-- Status line (under the bar, fades)
--------------------------------------------------------------------------------

local function SetStatus(text, r, g, b, stay, progress)
	if not status then return end
	if statusTimer then statusTimer:Cancel() statusTimer = nil end
	statusBox.fade:Stop()
	if not text or text == "" then statusBox:Hide() return end
	status:SetText(Pretty(text))
	status:SetTextColor(r or 0.9, g or 0.9, b or 0.9)
	statusBox.progress = progress
	statusBox:SetAlpha(1)
	statusBox:Show()
	Hang()
	if not stay then
		statusTimer = C_Timer.NewTimer(STATUS_HOLD, function()
			statusTimer = nil
			statusBox.fade:Play()
		end)
	end
end

local function Progress(p)
	SetStatus(L["Reading Questie's data... %d%%"]:format(p * 100), nil, nil, nil, true, p)
end

local function LightQuick(query)
	query = query and strtrim(query):lower()
	lit = nil
	for _, b in ipairs(quick) do
		if b.query and b.query == query and b:IsShown() then
			b.lit:Show()
			lit = query
		else
			b.lit:Hide()
		end
	end
	-- (one of the buttons under More: More is lit)
	local underMore = false
	for _, spec in ipairs(UI.ExtraSpecs and UI.ExtraSpecs() or {}) do
		if spec.query == query then underMore, lit = true, query end
	end
	if more then more.lit:SetShown(underMore) end
end

-- the search button lit while a typed search (not a quick button's) is on the map
local function LightSearch()
	-- (the X on the pinned quick button: click it to unpin)
	for _, b in ipairs(quick) do
		if b.unpin then b.unpin:SetShown(b.query ~= nil and b.query == ns.db.pinned) end
	end
	if not searchBtn then return end
	searchBtn.lit:SetShown(current ~= nil and lit == nil)
	-- (a search on the map: an X over the scope, to clear it; none, the scope opens the box)
	searchBtn.clear:SetShown(current ~= nil)
	searchBtn.icon:SetDesaturated(current ~= nil)
	searchBtn.icon:SetAlpha(current ~= nil and 0.55 or 1)
end

--------------------------------------------------------------------------------
-- Recent searches
--------------------------------------------------------------------------------

local function Remember(query)
	query = strtrim(query or ""):lower()
	if not ns.db.recent or #query < 2 then return end
	local h = ns.db.history
	for i = #h, 1, -1 do
		if h[i] == query then table.remove(h, i) end
	end
	table.insert(h, 1, query)
	for i = #h, RECENT_MAX + 1, -1 do h[i] = nil end
end

local FAVORITES_MAX = 20

local function IsFavorite(query)
	for _, q in ipairs(ns.db.favorites) do if q == query then return true end end
	return false
end

-- star a search (it stays at the top of the list), or take its star off
local function ToggleFavorite(query)
	local favs = ns.db.favorites
	for i = #favs, 1, -1 do
		if favs[i] == query then
			table.remove(favs, i)
			-- (unstarred: off the bar too)
			local key = UI.FavKey(query)
			for j = #ns.db.buttons, 1, -1 do
				if ns.db.buttons[j] == key then table.remove(ns.db.buttons, j) end
			end
			if UI.Layout then UI.Layout() end
			if ns.Settings.Refresh then ns.Settings.Refresh() end
			return
		end
	end
	if #favs >= FAVORITES_MAX then
		ns.Print(L["you can star up to %d searches; take the star off one first"]:format(FAVORITES_MAX))
		return
	end
	favs[#favs + 1] = query
	return true
end

UI.IsFavorite = IsFavorite
UI.FAVORITES_MAX = FAVORITES_MAX
function UI.ToggleFavorite(query) return ToggleFavorite(query) end

--- star a search, if it isn't (true: it's starred now)
function UI.Star(query)
	if IsFavorite(query) then return true end
	return ToggleFavorite(query)
end

--- is this favourite on the bar (or under More)?
function UI.OnBar(query)
	local key = UI.FavKey(query)
	for _, k in ipairs(ns.db.buttons) do if k == key then return true end end
	return false
end

--- a favourite onto the bar as a button of its own (its icon from what it finds), or off it
function UI.ToggleOnBar(query)
	local key, list = UI.FavKey(query), ns.db.buttons
	for i = #list, 1, -1 do
		if list[i] == key then
			table.remove(list, i)
			UI.Layout()
			if ns.Settings.Refresh then ns.Settings.Refresh() end
			return
		end
	end
	if not byQuery[query] and not ns.db.favIcons[query] then
		local look = "SEARCH"
		if ns.Index.done then
			local results, _, service = ns.Search.Run(query)
			local k = results and results[1] and ns.KindOf(results[1], service)
			if k and ns.LOOKS[k] then look = k end
		end
		ns.db.favIcons[query] = look
	end
	list[#list + 1] = key
	UI.Layout()
	if ns.Settings.Refresh then ns.Settings.Refresh() end
	local n = #UI.PickedKeys()
	if n > UI.MAX_BUTTONS then
		ns.Print(L["\"%s\" is under More (the bar holds %d); drag it along in the settings"]:format(query, UI.MAX_BUTTONS))
	end
end

--- the next icon for a favourite's button (back = the one before)
function UI.CycleIcon(query, back)
	if byQuery[query] then return end   -- (a quick search keeps its own)
	local cur, n = ns.db.favIcons[query] or "SEARCH", #UI.ICONS
	local at = 1
	for i, k in ipairs(UI.ICONS) do if k == cur then at = i end end
	at = ((at - 1 + (back and -1 or 1)) % n) + 1
	ns.db.favIcons[query] = UI.ICONS[at]
	UI.Layout()
	if ns.Settings.Refresh then ns.Settings.Refresh() end
end

local function Forget(query)
	local h = ns.db.history
	for i = #h, 1, -1 do
		if h[i] == query then table.remove(h, i) end
	end
end

--------------------------------------------------------------------------------
-- The drop-down under the box
--------------------------------------------------------------------------------

local SyncSearch   -- (below: the search box's strip closes once you're done with it)

local Unlook   -- (below: the map back, when the list closes on a row looked at)
local function HideList()
	sel = nil
	if list then list:Hide() end
	if Unlook then Unlook() end
	if SyncSearch then C_Timer.After(0, SyncSearch) end
end

function UI.ClearHistory()
	wipe(ns.db.history)
	HideList()
end

local function Highlight()
	for i, r in ipairs(rows) do r.sel:SetShown(i == sel) end
end

local Pick, ShowRecent, ShowFavorites, TogglePin, FollowGroup, RefreshMini   -- (below)
local listMode                     -- what the drop-down shows: "recent", "favs" or nil (suggestions)

-- the drop-down shown again, after a star, pin or bar button in it was clicked
local function RefreshList()
	if not (list and list:IsShown()) then return end
	if listMode == "favs" then ShowFavorites() else ShowRecent() end
end

local LOOK_ROW = { suggest = true, fix = true, recent = true, fav = true, pinned = true, farm = true, chain = true }
local chainQuery   -- a step of a quest line picked in the drop-down: what the map's back to after a look
local function Row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, list)
	r:SetHeight(ROW)
	r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW)
	r:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * ROW)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	local s = r:CreateTexture(nil, "BACKGROUND")
	s:SetAllPoints()
	s:SetColorTexture(1, 0.82, 0.1, 0.25)
	s:Hide()
	r.sel = s
	-- the X on a recent search: forget it
	local forget = CreateFrame("Button", nil, r)
	forget:SetSize(14, 14)
	forget:SetPoint("RIGHT", -4, 0)
	local ft = forget:CreateTexture(nil, "ARTWORK")
	ft:SetAllPoints()
	ft:SetTexture("Interface\\Buttons\\UI-StopButton")
	ft:SetVertexColor(1, 0.35, 0.3)
	ft:SetAlpha(0.6)
	ns.SkinClose(forget, ft)
	forget:SetScript("OnClick", function()
		if not (r.data and r.data.kind == "recent") then return end
		Forget(r.data.text)
		ShowRecent()
	end)
	forget:SetScript("OnEnter", function(self)
		ft:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Remove from recent searches"], 1, 1, 1)
		GameTooltip:Show()
	end)
	forget:SetScript("OnLeave", function()
		ft:SetAlpha(0.6)
		GameTooltip:Hide()
	end)
	r.forget = forget
	-- the star on a recent or starred search: click to star it, or take the star off
	local star = CreateFrame("Button", nil, r)
	star:SetSize(14, 14)
	star:SetPoint("RIGHT", -4, 0)
	local st = star:CreateTexture(nil, "ARTWORK")
	st:SetAllPoints()
	if st:SetTexture("Interface\\AddOns\\Questie\\Icons\\fav.tga") == false then
		st:SetTexture("Interface\\Common\\ReputationStar")
		st:SetTexCoord(0, 0.5, 0, 0.5)
	end
	star.tex = st
		star:SetScript("OnClick", function()
		if not r.data then return end
		ToggleFavorite(r.data.text)
		RefreshList()
	end)
	star:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(r.data and r.data.kind == "fav" and L["Take the star off"] or L["Star it: keep it at the top"], 1, 1, 1)
		GameTooltip:Show()
	end)
	star:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r.star = star
	-- the pin on a starred search: it stays on the map and minimap after the map closes
	local pin = CreateFrame("Button", nil, r)
	pin:SetSize(14, 14)
	pin:SetPoint("RIGHT", star, "LEFT", -4, 0)
	local pt = pin:CreateTexture(nil, "ARTWORK")
	pt:SetAllPoints()
	pt:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
	pt:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	pin.tex = pt
	pin:SetScript("OnClick", function()
		if r.data then TogglePin(r.data.text) end
	end)
	pin:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if r.data and ns.db.pinned == r.data.text then
			GameTooltip:AddLine(L["Pinned"], 1, 0.82, 0.1)
			GameTooltip:AddLine(L["It stays on the map and minimap after you close the map. Click to unpin it."], 1, 1, 1, true)
		else
			GameTooltip:AddLine(L["Pin it"], 1, 0.82, 0.1)
			GameTooltip:AddLine(L["Keep this search on the map and minimap after you close the map, until you unpin it."],
				1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r.pin = pin
	-- on a starred search: put it on the bar as a button of its own
	local onBar = CreateFrame("Button", nil, r)
	onBar:SetSize(14, 14)
	onBar:SetPoint("RIGHT", pin, "LEFT", -4, 0)
	local bt = onBar:CreateTexture(nil, "ARTWORK")
	bt:SetAllPoints()
	onBar.tex = bt
	onBar:SetScript("OnClick", function()
		if not r.data then return end
		UI.ToggleOnBar(r.data.text)
		RefreshList()
	end)
	onBar:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if r.data and UI.OnBar(r.data.text) then
			GameTooltip:AddLine(L["On the bar"], 1, 0.82, 0.1)
			GameTooltip:AddLine(L["It has a button of its own. Click to take it off."], 1, 1, 1, true)
		else
			GameTooltip:AddLine(L["Put it on the bar"], 1, 0.82, 0.1)
			GameTooltip:AddLine(L["A button of its own, beside the others (under More once the bar has 5). Change its icon in the settings."], 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	onBar:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r.onBar = onBar
	local hint = ns.Text(r, "GameFontDisableSmall")
	hint:SetPoint("RIGHT", -6, 0)
	r.hint = hint
	-- what it is, at its left: an item, an NPC, a place, a recent search...
	local icon = r:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("LEFT", 5, 0)
	r.icon = icon
	local t = ns.Text(r, "GameFontHighlightSmall")
	t:SetPoint("LEFT", icon, "RIGHT", 5, 0)
	t:SetPoint("RIGHT", hint, "LEFT", -6, 0)
	t:SetJustifyH("LEFT")
	t:SetWordWrap(false)
	r.text = t
	ns.SkinText(t, hint)
	r:SetScript("OnClick", function(self, button)
		local d = self.data
		if not d then return end
		-- (a farm's row is its item: shift-click links it in chat, as an item anywhere)
		if d.kind == "farm" and button == "LeftButton" and (IsShiftKeyDown() or IsControlKeyDown()) then
			local id = UI.FarmItem(d)
			local link = id and select(2, ItemInfo(id))
			if link then
				if HandleModifiedItemClick then HandleModifiedItemClick(link)
				elseif IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
			end
			return
		end
		if button == "RightButton" then
			if d.kind == "recent" then
				Forget(d.text)
				ShowRecent()
			elseif d.kind == "fav" then
				ToggleFavorite(d.text)
				RefreshList()
			elseif d.kind == "pinned" then
				TogglePin(d.text)
			end
			return
		end
		Pick(d)
	end)
	r:SetScript("OnEnter", function(self)
		local k = self.data and self.data.kind
		-- (looked at: it on the map, and the one Enter takes)
		if LOOK_ROW[k] then
			sel = i
			Highlight()
			UI.PreviewFarm(self.data)
		end
		if k == "recent" or k == "fav" or k == "pinned" then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.data.label or self.data.text, 1, 0.82, 0.1)
			GameTooltip:AddLine(L["Click to search again"], 1, 1, 1)
			GameTooltip:AddLine(k == "fav" and L["Right-click to take the star off"]
				or k == "pinned" and L["Right-click to unpin it"] or L["Right-click to forget it"], 0.7, 0.7, 0.7)
			GameTooltip:Show()
		elseif k == "farm" then
			local o = self.data.farm
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(L["Farming %s in %s"]:format(self.data.title or "?", o.zone), 1, 0.82, 0.1)
			if o.mob and (o.unknown or o.nodes < 1) then
				GameTooltip:AddLine(L["A loop of %d camps of the mobs that drop it, %s a lap."]:format(#o.spots,
					ns.Route.Minutes(o.secs)), 1, 1, 1, true)
				GameTooltip:AddLine(o.unknown and L["How often they drop it isn't known."] or L["They seldom drop it."], 0.7, 0.7, 0.7, true)
			elseif o.mob then
				GameTooltip:AddLine(L["A loop of %d camps of the mobs that drop it: about %d drops and %s a lap."]:format(#o.spots,
					math.floor(o.nodes + 0.5), ns.Route.Minutes(o.secs)), 1, 1, 1, true)
			else
				GameTooltip:AddLine(L["%d spawn points on a loop of %d spots, about %s a lap."]:format(o.nodes, #o.spots,
					ns.Route.Minutes(o.secs)), 1, 1, 1, true)
			end
			if o.how and FARM_HOW[o.how] then GameTooltip:AddLine(FARM_HOW[o.how], 0.69, 0.82, 1) end
			if o.wanted then
				GameTooltip:AddLine(o.wanted > 1 and L["Quests ask for it: %s, and %d more."]:format(o.wantedBy or "?", o.wanted - 1)
					or L["A quest asks for it: %s."]:format(o.wantedBy or "?"), 0.6, 1, 0.6, true)
			end
			if ns.Farm.Worth and ns.db.farmWorth ~= false then
				local low, high = ns.Farm.Worth(o, self.data.title)
				if low and high >= 100 then
					GameTooltip:AddLine(L["Might make %s to %s an hour at auction."]:format(Coins(low), Coins(high)), 1, 0.82, 0.1, true)
					GameTooltip:AddLine(L["A guess: today's prices, and every lap as full as the data says."], 0.7, 0.7, 0.7, true)
				end
			end
			if o.lock and select(2, UnitClass("player")) ~= "ROGUE" then
				GameTooltip:AddLine(L["Lockpicking: only rogues can pick these."], 1, 0.4, 0.4, true)
			end
			if o.high then
				GameTooltip:AddLine((o.mob and L["Its mobs are level %d and up, far above you: not one to do yet."]
					or L["The zone is level %d and up, far above you: not one to do yet."]):format(o.high), 1, 0.4, 0.4, true)
			end
			if UI.FarmItem(self.data) then GameTooltip:AddLine(L["Shift-click to link the item in chat."], 0.7, 0.7, 0.7, true) end
			if o.more then
				GameTooltip:AddLine(L["Click or press Enter for its loops, zone by zone."], 0.7, 0.7, 0.7, true)
			else
				GameTooltip:AddLine(L["Click or press Enter to ride it. It goes round until you stop it: /seek stop, or the X on the map's route panel."], 0.7, 0.7, 0.7, true)
			end
			GameTooltip:Show()
		elseif k == "chain" then
			local s = self.data.step
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(s.name, 1, 0.82, 0.1)
			GameTooltip:AddLine(L["Step %d of %d"]:format(self.data.n, self.data.of), 1, 1, 1)
			if s.done then GameTooltip:AddLine(L["You've done this one."], 0.6, 0.6, 0.6)
			elseif s.inLog then GameTooltip:AddLine(L["You're on this one."], 0.5, 1, 0.5)
			elseif self.data.here then GameTooltip:AddLine(L["You're up to this one."], 0.5, 1, 0.5) end
			GameTooltip:AddLine(L["Click to see it on the map: who starts it, or where to go for it if you're on it."], 0.7, 0.7, 0.7, true)
			GameTooltip:Show()
		elseif k == "addfav" then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(L["Star this search"], 1, 0.82, 0.1)
			GameTooltip:AddLine(L["Add it to your favourites, to pin it or put it on the bar."], 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = r
	return r
end

-- a favourite as the list shows it: a quick search by its name (Repair), else as typed
local function FavLabel(q)
	local spec = byQuery[q]
	return spec and spec.label or nil
end

local function Fill(data)
	listData, sel = data, nil
	if not list or #data == 0 then HideList() return end
	local y = 4   -- (where the next row goes, down from the list's top)
	local wide = LIST_WIDTH
	for i, d in ipairs(data) do
		local r = Row(i)
		r.data = d
		-- (a message, "nothing found" and why: wrapped onto as many lines as it takes, the row as
		-- tall as they are. Anything else, one line)
		local wrap = d.kind == "none"
		r.text:SetWordWrap(wrap)
		r.text:SetText(d.label or d.text)
		local h = ROW
		if wrap then
			r.text:SetHeight(0)
			h = math.max(ROW, math.ceil(r.text:GetStringHeight()) + 6)
		end
		r:SetHeight(h)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 4, -y)
		r:SetPoint("TOPRIGHT", -4, -y)
		y = y + h
		if d.kind == "fix" then
			r.text:SetTextColor(0.5, 1, 0.5)
		else
			r.text:SetTextColor(1, 1, 1)
		end
		-- (a farm's row: its item's colour, when it's better than common)
		if d.kind == "farm" then
			local id = UI.FarmItem(d)
			local quality = id and select(3, ItemInfo(id))
			local c = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
			if c then r.text:SetTextColor(c.r, c.g, c.b) end
		end
		r.hint:SetText(d.hint or "")
		if d.kind == "addfav" then r.text:SetTextColor(0.5, 1, 0.5)
		elseif d.kind == "manage" then r.text:SetTextColor(1, 0.82, 0.1)
		elseif d.kind == "empty" then r.text:SetTextColor(0.6, 0.6, 0.6)
		elseif d.kind == "none" then r.text:SetTextColor(1, 0.35, 0.35)
		elseif d.kind == "chain" then
			-- (a quest line's steps: done ones grey, the one you're up to gold)
			if d.step.done and not d.step.inLog then r.text:SetTextColor(0.6, 0.6, 0.6)
			elseif d.here then r.text:SetTextColor(1, 0.82, 0.1) end
		end
		local look = (d.kind == "suggest" or d.kind == "farm") and ICONS[d.sub] or ICONS[d.kind]
		if d.icon then look = { d.icon, true } end   -- (its own: a farming loop's herb or ore)
		if look then
			r.icon:SetTexture(look[1])
			if look[2] == true then r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			elseif type(look[2]) == "table" then r.icon:SetTexCoord(unpack(look[2]))
			else r.icon:SetTexCoord(0, 1, 0, 1) end
			r.icon:SetDesaturated(d.kind == "recent")
			r.icon:SetAlpha(d.kind == "recent" and 0.6 or 0.9)
			r.icon:Show()
		else
			r.icon:Hide()
		end
		-- (recent and starred searches carry the star, lit on starred ones; starred and pinned
		-- ones the pin, lit on the pinned one; starred ones the bar button. The hint moves aside)
		local starred = d.kind == "fav"
		local recent = d.kind == "recent"
		r.forget:SetShown(recent)
		r.star:ClearAllPoints()
		if recent then r.star:SetPoint("RIGHT", r.forget, "LEFT", -4, 0) else r.star:SetPoint("RIGHT", -4, 0) end
		r.star:SetShown(starred or recent or d.kind == "pinned")
		r.star.tex:SetDesaturated(not starred)
		r.star.tex:SetAlpha(starred and 1 or 0.35)
		local pinned = ns.db.pinned == d.text
		r.pin:SetShown(starred or d.kind == "pinned")
		r.pin.tex:SetDesaturated(not pinned)
		r.pin.tex:SetAlpha(pinned and 1 or 0.35)
		local barred = starred and UI.OnBar(d.text)
		r.onBar:SetShown(starred)
		r.onBar.tex:SetTexture(barred and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
		r.hint:ClearAllPoints()
		if r.onBar:IsShown() then r.hint:SetPoint("RIGHT", r.onBar, "LEFT", -4, 0)
		elseif r.pin:IsShown() then r.hint:SetPoint("RIGHT", r.pin, "LEFT", -4, 0)
		elseif r.star:IsShown() then r.hint:SetPoint("RIGHT", r.star, "LEFT", -4, 0)
		else r.hint:SetPoint("RIGHT", -6, 0) end
		r:Show()
		-- (what the row needs to show all of itself: its icon, its name, its hint, its buttons)
		if not wrap then
			local name = r.text.GetUnboundedStringWidth and r.text:GetUnboundedStringWidth() or r.text:GetStringWidth() or 0
			local buttons = 0
			for _, b in ipairs({ r.forget, r.star, r.pin, r.onBar }) do
				if b and b:IsShown() then buttons = buttons + 20 end
			end
			wide = math.max(wide, 24 + name + 6 + (r.hint:GetStringWidth() or 0) + 12 + buttons + 8)
		end
	end
	list:SetWidth(math.min(LIST_WIDEST, math.ceil(wide)))
	for i = #data + 1, #rows do
		rows[i]:Hide()
		rows[i].data = nil
	end
	Highlight()
	list:SetHeight(y + 4)
	list:Show()
end

function ShowRecent()
	listMode = "recent"
	local data = {}
	-- (the pinned search first, when it isn't starred: always here to unpin, history or not)
	local pin = ns.db.pinned
	if pin and not IsFavorite(pin) then data[1] = { text = pin, hint = L["pinned"], kind = "pinned" } end
	-- (your favourites, but not those with a button on the bar: they're a click away already. The
	-- star at the end of the box lists them all)
	for _, q in ipairs(ns.db.favorites) do
		if not UI.OnBar(q) then data[#data + 1] = { text = q, label = FavLabel(q), kind = "fav" } end
	end
	if ns.db.recent then
		local left = ns.db.recentMax or 3
		for _, q in ipairs(ns.db.history) do
			if left <= 0 then break end
			if not IsFavorite(q) and q ~= pin then
				data[#data + 1] = { text = q, hint = L["recent"], kind = "recent" }
				left = left - 1
			end
		end
	end
	Fill(data)
end

-- your favourites (the star at the end of the search box): the search on the map, to star it;
-- the pinned search; the starred ones, each to pin or put on the bar; and the settings for them
function ShowFavorites()
	listMode = "favs"
	local data = {}
	local q = current and strtrim(current):lower()
	if q and q ~= "" and not IsFavorite(q) then
		data[#data + 1] = { text = q, hint = L["star it"], kind = "addfav" }
	end
	local pin = ns.db.pinned
	if pin and not IsFavorite(pin) then data[#data + 1] = { text = pin, hint = L["pinned"], kind = "pinned" } end
	for _, f in ipairs(ns.db.favorites) do data[#data + 1] = { text = f, label = FavLabel(f), kind = "fav" } end
	if #ns.db.favorites == 0 then
		data[#data + 1] = { text = L["No favourites yet: search, then star it here"], kind = "empty" }
	end
	data[#data + 1] = { text = L["Manage favourites..."], kind = "manage" }
	Fill(data)
end

-- suggestions for what's typed, with a spelling fix on top when there's little else
local function ShowSuggest(text, withFix)
	listMode = nil
	local data = {}
	local fix, unsold = nil, nil
	if withFix then fix, unsold = ns.Suggest.Correct(text) end
	if unsold then fix = nil end   -- (it'd find nothing: no vendor sells it)
	if fix then data[1] = { text = fix, hint = L["did you mean"], kind = "fix" } end
	for _, s in ipairs(ns.Suggest.For(text)) do
		if #data >= 8 then break end
		if not (fix and s.text:lower() == fix) then
			data[#data + 1] = { text = s.text, hint = s.hint, kind = "suggest", sub = s.kind }
		end
	end
	Fill(data)
	return #data
end

-- after a search that's as like two places or more ("razorfen", "plaguelands"): those places, to
-- pick one (and go there). Once the search is done: a moment later, as Enter takes the box's focus
-- (and the list with it) after the search
local choiceRun = 0
local function ShowChoices(choices)
	choiceRun = choiceRun + 1
	local run = choiceRun
	C_Timer.After(0, function()
		if run ~= choiceRun or not list then return end
		listMode = nil
		local data = {}
		for _, p in ipairs(choices) do
			data[#data + 1] = { text = p.name, hint = ns.Suggest.PlaceHint(p), kind = "fix" }
		end
		Fill(data)
		-- (back in the box, as Enter took it out: the arrow keys go through the list and Enter
		-- picks, as with the suggestions; Esc leaves)
		if edit and list:IsShown() and not edit:HasFocus() then edit:SetFocus() end
	end)
end

-- a search that found nothing, on Enter: what's typed blinks red for a moment, then is as it
-- was, still there to change; and the list under the box says so, as "Did you mean" would
local BLINK_FOR, BLINK_EVERY = 2, 0.25
local blinkTicker, blinkColor

local function StopBlink()
	if blinkTicker then blinkTicker:Cancel() blinkTicker = nil end
	if blinkColor and edit then edit:SetTextColor(blinkColor[1], blinkColor[2], blinkColor[3]) end
	blinkColor = nil
end

local function NoResults(msg)
	choiceRun = choiceRun + 1
	local run = choiceRun
	StopBlink()
	if edit then
		local r, g, b = edit:GetTextColor()
		blinkColor = { r or 1, g or 1, b or 1 }
		local n, total = 0, math.floor(BLINK_FOR / BLINK_EVERY)
		edit:SetTextColor(1, 0.25, 0.25)
		blinkTicker = C_Timer.NewTicker(BLINK_EVERY, function()
			n = n + 1
			if n >= total or not edit then StopBlink() return end
			if n % 2 == 0 then edit:SetTextColor(1, 0.25, 0.25)
			else edit:SetTextColor(blinkColor[1], blinkColor[2], blinkColor[3]) end
		end, total)
	end
	C_Timer.After(0, function()
		if run ~= choiceRun or not list then return end
		listMode = nil
		Fill({ { text = msg or "", kind = "none" } })
		-- (back in the box, as Enter took it out: to change what's typed, or clear it)
		if edit and not edit:HasFocus() then edit:SetFocus() end
	end)
end

local function MakeList()
	local ok, f = pcall(CreateFrame, "Frame", "MapSeekList", bar, "BackdropTemplate")
	if not ok or not f then f = CreateFrame("Frame", "MapSeekList", bar) end
	f:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -8, -2)
	f:SetWidth(LIST_WIDTH)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	Flat(f)
	f:Hide()
	return f
end

--------------------------------------------------------------------------------
-- Searching
--------------------------------------------------------------------------------

local function SetNear(d)
	if not near then return end
	near.target = d
	near.icon:SetDesaturated(not d)
	near.icon:SetAlpha(d and 1 or 0.4)
end

local function Yards(yd)
	return yd and " " .. L["(%d yd)"]:format(yd) or ""
end

-- your group's markers, moved to where they are now every few seconds while that search is
-- the one on the map (open or closed: the minimap's too), until another search or a clear
local GROUP_EVERY = 2
local groupTicker
function FollowGroup(query)
	if groupTicker then groupTicker:Cancel() end
	groupTicker = C_Timer.NewTicker(GROUP_EVERY, function(self)
		if current ~= query or not ns.Pins.Available() then
			self:Cancel()
			if groupTicker == self then groupTicker = nil end
			return
		end
		local results = ns.Search.Group(query)
		if results then
			local _, _, nearest = ns.Pins.Show(results, nil, true, query == ns.db.pinned)
			SetNear(nearest)
		end
	end)
end

--- source: "quick" (a quick button: not kept in recents), "enter", "slash", "recent" (kept),
--- "again" (the same search, shown again for the map now: quiet, not kept), or nil (as you
--- type: kept once you're done typing)
--------------------------------------------------------------------------------
-- Going to a place (a search that names a zone, city, continent or dungeon)
--------------------------------------------------------------------------------

-- With OpenMap's stitched map: out to a view with both where you are and where you're going,
-- a moment there, then in to the place (OpenMap's glides, 0.4 s each: its API doesn't take a
-- length). Then the map is set to the place, which puts it whole and its breadcrumb up
local FLY_GLIDE = 0.45          -- a glide of OpenMap's, and a little over
local FLY_HOLD = 0.7            -- seconds the zoomed-out view stays, between the two
local QUICK_HOLD = 0.12         -- (a quick look, a farming loop hovered: hardly a pause)
local QUICK_NEAR = 0.6          -- (and straight there when it's this near, in views' widths)
local flight = 0                -- the latest move: a newer one (or the map closing) stops an older

local SPOT_ZOOM = 3            -- a town or a dungeon's entrance: this much closer in than its whole zone
local RESULT_ZOOM = 1.5        -- a search's nearest result: a little closer than its whole zone

--- whether the world map is OpenMap's stitched one now (its glides take the map places)
function UI.Stitched()
	return OpenMapAPI and OpenMapAPI.IsStitched and OpenMapAPI.IsStitched() or false
end

--- the map to map `id`; or, with x, y (0..1 on it), to that spot of it, `zoom` times closer in
--- than the whole map (SPOT_ZOOM when not given). quick: a look, not a journey (straight there
--- when it's near, else out and in with hardly a pause)
function UI.GoToMap(id, x, y, zoom, quick)
	flight = flight + 1
	local me = flight
	if not WorldMapFrame:IsShown() then
		if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
		-- (once the map, and OpenMap's view, are up)
		C_Timer.After(0.1, function() if me == flight and WorldMapFrame:IsShown() then UI.GoToMap(id, x, y, zoom, quick) end end)
		return
	end
	local api = OpenMapAPI
	local stitched = api and api.IsStitched and api.IsStitched()
	local l, t, r, b, u0, v0, z0
	if stitched then
		l, t = api.WorldFromMap(id, 0, 0)
		r, b = api.WorldFromMap(id, 1, 1)
		u0, v0, z0 = api.GetView()
	end
	local function Land()
		if me ~= flight or not WorldMapFrame:IsShown() then return end
		if WorldMapFrame:GetMapID() ~= id then WorldMapFrame:SetMapID(id) end
	end
	if not (l and r and u0 and z0 and z0 > 0) then Land() return end   -- (Blizzard's map, or no place on OpenMap's)

	local u1, v1 = (l + r) / 2, (t + b) / 2
	-- (zoom 1: the whole world fits; this fits the place, or a little more of it shows)
	local zIn = 0.95 / math.max(math.abs(r - l), math.abs(b - t), 1e-4)
	if x and y then
		-- (a spot in it: there, closer in. OpenMap puts the zone's map under it, breadcrumb and
		-- all, as it does for any view that close: setting the map would show the whole zone)
		u1, v1 = l + (r - l) * x, t + (b - t) * y
		zIn = zIn * (zoom or SPOT_ZOOM)
		Land = function() end
	end
	local function In()
		if me ~= flight or not WorldMapFrame:IsShown() then return end
		api.ShowWorld(u1, v1, zIn)
		C_Timer.After(FLY_GLIDE, Land)
	end
	local du, dv = math.abs(u1 - u0), math.abs(v1 - v0)
	-- (a place already in view: straight there. Anywhere else out and in, even to a bigger place
	-- shown further out: straight there, that's a long pan at much the same zoom)
	local near = quick and QUICK_NEAR or 0.35
	if du < near / z0 and dv < near / z0 then In() return end
	local zOut = math.min(z0 * 0.6, zIn, 0.35 / math.max(du, dv))
	api.ShowWorld((u0 + u1) / 2, (v0 + v1) / 2, zOut)
	C_Timer.After(FLY_GLIDE + (quick and QUICK_HOLD or FLY_HOLD), In)
end

-- the map to a place a search named; true if it did
local function GoPlace(p, query)
	HideList()
	Remember(query)
	UI.GoToMap(p.id)
	SetStatus(("%s (%s)"):format(p.name, L[p.kind]), 0.6, 1, 0.6)
	return true
end

-- a town, or a dungeon's entrances: markers on them, as a search's (cleared, pinned and kept after
-- the map closes as one), and the map to the nearest. Again (a setting changed, the map moved):
-- the markers only
local function ShowSpots(p, query, source)
	HideList()
	if source ~= "again" then
		Remember(query)
		lastTyped = nil
	end
	LightQuick(query)
	current = query
	pending = nil
	local pts = {}
	for i, at in ipairs(p.points) do pts[i] = { ui = at.ui, x = at.x * 100, y = at.y * 100 } end
	local r = { entry = { id = 0, name = p.name, obj = true, flags = 0 }, rank = 0, near = false,
		kind = p.kind == "dungeon" and "DUNGEON" or "TOWN", points = pts }
	local _, _, nearest = ns.Pins.Show({ r }, nil, source == "again", query == ns.db.pinned)
	SetNear(nearest)
	local go = nearest and { ui = nearest.ui, x = nearest.x / 100, y = nearest.y / 100 } or p.points[1]
	if source ~= "again" then UI.GoToMap(go.ui, go.x, go.y) end
	local where = ns.ZoneName(go.ui) or "?"
	if #pts > 1 then where = where .. " " .. L["(%d entrances)"]:format(#pts) end
	SetStatus(("%s, %s"):format(p.name, where), 0.6, 1, 0.6)
	LightSearch()
end

-- a farming loop's zone on the map: every vein or plant of it there marked, the map on it.
-- Again (the map changed): the markers only, of the loop shown last
local farmShown   -- { query, o }: the loop whose markers are on the map
local slowGo      -- (a list of farms being worked out: its search)
local previewRun = 0   -- (the latest row looked at: an older look waiting is dropped)
--- the item a farm's row is of (a vein's ore, a herb, what the mobs drop), or nil: a lockbox's,
--- a tier of crates'
function UI.FarmItem(d)
	local o = d and d.farm
	if not o or o.lock or o.mix then return end
	return o.item or (ns.Farm.ItemOf and ns.Farm.ItemOf(d.title)) or nil
end

-- what an hour of a farm might make at auction, for its row: " 8g-14g/h" in gold, or ""
local function WorthHint(o, title)
	if not (ns.Farm.Worth and ns.db.farmWorth ~= false) then return "" end
	local low, high = ns.Farm.Worth(o, title)
	if not low or high < 100 then return "" end
	local span = Coins(low) == Coins(high) and Coins(high) or (Coins(low) .. "-" .. Coins(high))
	return "  |cffffd100" .. L["%s/h"]:format(span) .. "|r"
end

-- a lockpicking row's hint: the skill its boxes ask, red when it's more than yours (or the zone's
-- too high for you)
local function Rogue()
	local _, class = UnitClass("player")
	return class == "ROGUE"
end
local function LockHint(o)
	local mine = ns.Farm.LockSkill and ns.Farm.LockSkill()
	local need = o.skillTo and ("%d-%d"):format(o.skill, o.skillTo) or tostring(o.skill)
	-- (not a rogue: every one's out of reach)
	if not Rogue() then return "|cffff6040" .. L["Lockpicking %s: rogues only"]:format(need) .. "|r" end
	if mine and mine < o.skill then
		return "|cffff6040" .. L["needs Lockpicking %s"]:format(need) .. "|r"
	end
	if o.high then return "|cffff6040" .. L["Lockpicking %s; level %d+ zone"]:format(need, o.high) .. "|r" end
	return L["Lockpicking %s, %d boxes"]:format(need, o.count or o.nodes)
end

local function FarmShow(o, title, nodes, query, again, quick)
	title, nodes = o.title or title, o.own or nodes   -- (a zone's farms: each row its own)
	farmShown = { query = query, o = o }
	if ns.Farm.Ways then ns.Farm.Ways(o) end
	if ns.Route.Preview then ns.Route.Preview(o) end
	local _, _, nearest = ns.Pins.Show(ns.Farm.Results(o, nodes, title), nil, again, query == ns.db.pinned)
	SetNear(nearest)
	if again then return end
	-- (the loop in view, filling it: its middle, as close in as shows all of it)
	local x0, y0, x1, y1 = 100, 100, 0, 0
	for _, p in ipairs(o.spots) do
		x0, y0, x1, y1 = math.min(x0, p.x), math.min(y0, p.y), math.max(x1, p.x), math.max(y1, p.y)
	end
	local zoom = math.max(1, math.min(SPOT_ZOOM, 75 / math.max(x1 - x0, y1 - y0, 1)))
	UI.GoToMap(o.ui, (x0 + x1) / 200, (y0 + y1) / 200, zoom, quick)
end

--- a farming loop ridden, not picked from the drop-down (a farm list's next thing): its markers
--- on the map, and off round it. true when it's begun. With the map closed: the markers only,
--- the map left as it was
function UI.RideFarm(o, title, nodes, query)
	previewRun = previewRun + 1
	if WorldMapFrame and WorldMapFrame:IsShown() then
		FarmShow(o, title, nodes, query)
	else
		farmShown = { query = query, o = o }
		if ns.Farm.Ways then ns.Farm.Ways(o) end
		pcall(ns.Pins.Show, ns.Farm.Results(o, nodes, title), nil, false, false)
	end
	return ns.Farm.Start(o, title) and true or false
end

--- a farming loop in the drop-down looked at (hovered, or picked with the arrow keys): its zone on
--- the map, every vein or plant of it there marked, the loop drawn
local PREVIEW_WAIT = 0.2       -- seconds on a row before the map goes to it (passing over: nothing)
local LOOK = { suggest = true, fix = true, recent = true, fav = true, pinned = true, chain = true }
function UI.PreviewFarm(d)
	if not d then return end
	if d.kind == "farm" and d.farm then
		previewRun = previewRun + 1
		local run = previewRun
		C_Timer.After(PREVIEW_WAIT, function()
			if run ~= previewRun or (farmShown and farmShown.o == d.farm) then return end
			-- (picked meanwhile: the loop's own route is on, nothing to look at)
			if ns.Route.Active and ns.Route.Active() then return end
			FarmShow(d.farm, d.title, d.nodes, d.text, false, true)
		end)
	elseif LOOK[d.kind] and d.text and d.text ~= "" then
		-- (any other search in the list: its markers, the map to the nearest, as if typed)
		previewRun = previewRun + 1
		local run = previewRun
		C_Timer.After(PREVIEW_WAIT, function()
			if run ~= previewRun or not (list and list:IsShown()) then return end
			if previewing and lookedAt == d.text then return end
			UI.Run(d.text, "preview")
			previewing, lookedAt = true, d.text
		end)
	end
end

-- the list closed on a row looked at, none picked: the map back to what's in the box (its search
-- as typed; nothing, when it's empty)
function Unlook()
	if not previewing then return end
	previewing, lookedAt = false, nil
	previewRun = previewRun + 1
	local text = chainQuery or (edit and strtrim(Plain(edit:GetText()) or "") or "")
	if text ~= "" then
		UI.Run(text, "again")
	else
		if ns.Route.Preview then ns.Route.Preview(nil) end
		current, farmShown = nil, nil
		ns.Pins.Clear()
		SetNear(nil)
		SetStatus(nil)
		LightSearch()
	end
end

-- a farming search ("copper farm"): the loops in the drop-down, to pick one; the best one's
-- zone on the map meanwhile. (Once the search is done, as the choices are: Enter takes the list)
local function ShowFarm(query, opts, title, nodes)
	Remember(query)
	-- (one thing's farm: its name in the box becomes the item's link, "[Heavy Scorpid Scale] farm".
	-- An item the game hasn't got yet: asked for, and tried again a moment on)
	local first = opts[1]
	if edit and first and not first.more then
		local id = UI.FarmItem({ farm = first, title = first.title or title })
		local function Link(tries)
			if not id or strtrim(Plain(edit:GetText()) or ""):lower() ~= strtrim(query):lower() then return end
			local name, link = ItemInfo(id)
			if not (name and link) then
				if tries > 0 then C_Timer.After(0.5, function() Link(tries - 1) end) end
				return
			end
			local low, s0, e0 = query:lower(), nil, nil
			for _, n in ipairs({ name:lower(), (name:lower():gsub("'", "")) }) do
				s0, e0 = low:find(n, 1, true)
				if s0 then break end
			end
			if s0 then edit:SetText(query:sub(1, s0 - 1) .. link .. query:sub(e0 + 1)) end
		end
		Link(4)
	end
	lastTyped = nil
	current = query
	FarmShow(opts[1], title, nodes, query)
	LightSearch()
	-- (only mobs far above you drop it: shown all the same, said plainly)
	local allHigh = #opts > 0
	for _, o in ipairs(opts) do if not o.high then allHigh = false end end
	if opts[1] and opts[1].lock and not Rogue() then
		SetStatus(L["Lockpicking: only rogues can pick these."], 1, 0.4, 0.4)
	elseif allHigh then
		SetStatus(L["%s: nothing near your level drops it. These loops are for higher levels."]:format(title), 1, 0.4, 0.4)
	else
		SetStatus(L["%s: pick a farming loop"]:format(title), 0.6, 1, 0.6)
	end
	local l = title:lower()
	local sub = (l:find("vein$") or l:find("deposit$")) and "ore" or "herb"
	choiceRun = choiceRun + 1
	local run = choiceRun
	C_Timer.After(0, function()
		if run ~= choiceRun or not list then return end
		listMode = nil
		local data = {}
		for _, o in ipairs(opts) do
			-- (a zone's farms: each row named for what it farms; things farmed together: the split)
			local t = o.title or title
			local tl = t:lower()
			data[#data + 1] = { text = query, label = o.label or (o.mixText and (o.zone .. ": " .. o.mixText)) or o.zone, kind = "farm",
				sub = o.title and ((tl:find("vein$") or tl:find("deposit$")) and "ore" or "herb") or sub,
				farm = o, title = t, nodes = o.own or nodes,
				icon = ns.Farm.Icon and ns.Farm.Icon(t),
				hint = o.skill and LockHint(o)
					or o.high and ("|cffff6040" .. (o.mob and L["level %d+ mobs: too high for you"]
						or L["level %d+ zone: too high for you"]):format(o.high) .. "|r")
					or o.unknown and L["drop chance not known, %s a lap"]:format(ns.Route.Minutes(o.secs))
					or o.mob and o.nodes < 1 and L["a rare drop, %s a lap"]:format(ns.Route.Minutes(o.secs))
					or o.mob and L["about %d drops, %s a lap"]:format(math.floor(o.nodes + 0.5), ns.Route.Minutes(o.secs))
					or L["%d spawns, %s a lap"]:format(o.nodes, ns.Route.Minutes(o.secs)) }
			data[#data].hint = data[#data].hint .. WorthHint(o, t)
			-- (a money maker's row: the kind of farming it is, first)
			local how = o.how and FARM_HOW[o.how]
			if how then data[#data].hint = "|cffb0d0ff" .. how .. "|r  " .. data[#data].hint end
		end
		Fill(data)
		-- (the first one, shown on the map already, is the one Enter takes, till another's looked at)
		sel = 1
		Highlight()
		if edit and list:IsShown() and not edit:HasFocus() then edit:SetFocus() end
	end)
end

-- a quest in a line: its steps in the drop-down, the one you're up to (or the one picked) lit; each
-- to look at, and to click to see it. At most this many: the ones round where you are
local CHAIN_ROWS = 12
local CHAIN_ICON = { done = "Interface\\RaidFrame\\ReadyCheck-Ready", log = "Interface\\GossipFrame\\ActiveQuestIcon",
	open = "Interface\\GossipFrame\\AvailableQuestIcon" }
local function ShowChain(c)
	choiceRun = choiceRun + 1
	local run = choiceRun
	C_Timer.After(0, function()
		if run ~= choiceRun or not list then return end
		listMode = nil
		local n = #c.steps
		local mid = c.look or c.at or n
		local first = math.max(1, math.min(mid - math.floor(CHAIN_ROWS / 2), n - CHAIN_ROWS + 1))
		local last = math.min(n, first + CHAIN_ROWS - 1)
		local data, pick = {}, nil
		if first > 1 then data[#data + 1] = { kind = "empty", label = L["%d steps before"]:format(first - 1) } end
		for i = first, last do
			local s = c.steps[i]
			local here = i == c.at
			data[#data + 1] = { kind = "chain", text = "quest #" .. s.id, step = s, n = i, of = n, here = here,
				label = ("%d. %s%s"):format(i, s.level and s.level > 0 and ("[" .. s.level .. "] ") or "", s.name),
				hint = s.inLog and L["on it"] or (s.done and L["done"]) or (here and L["next"]) or nil,
				icon = s.inLog and CHAIN_ICON.log or (s.done and CHAIN_ICON.done) or CHAIN_ICON.open }
			if i == mid then pick = #data end
		end
		if last < n then data[#data + 1] = { kind = "empty", label = L["%d steps after"]:format(n - last) } end
		Fill(data)
		sel = pick
		Highlight()
		if edit and list:IsShown() and not edit:HasFocus() then edit:SetFocus() end
	end)
end

-- searches to go on to (a faction's things to bring: where each drops, a loop to farm it; the
-- factions with turn-ins), in the drop-down: each one searched when it's picked
local function ShowGoTo(rows)
	choiceRun = choiceRun + 1
	local run = choiceRun
	C_Timer.After(0, function()
		if run ~= choiceRun or not list then return end
		listMode = nil
		local data = {}
		for _, c in ipairs(rows) do
			data[#data + 1] = { kind = "goto", text = c.text, label = c.label, hint = c.hint, icon = c.icon }
		end
		Fill(data)
		sel = nil
		Highlight()
		if edit and list:IsShown() and not edit:HasFocus() then edit:SetFocus() end
	end)
end

-- a search, inside the place it names if it names one ("herb trainer org": herb trainers in
-- Orgrimmar). Nothing there: the whole thing as a search ("booty bay bruiser" is an NPC), and
-- failing that, the place's own "none here". The place comes back last
local function SearchIn(query)
	local rest, p = ns.Search.SplitPlace(query)
	if not (rest and #rest >= 2) then return ns.Search.Run(query) end
	local r, m, s, e = ns.Search.Run(rest, true, p.id)
	if r then return r, m, s, e, p end
	local r2, m2, s2, e2 = ns.Search.Run(query)
	if r2 then return r2, m2, s2, e2 end
	return nil, m, s, e
end

-- Shh. "gm island": an island that isn't anywhere, drawn out in the open sea (Pins.ShowIsland),
-- somewhere new each time. Not a place, not in the recent searches, no hint as it's typed. Its
-- other words go to one of its people. Every word is one no real NPC, item, object or place has
-- in its name (checked against the whole of Questie's data), so nothing real is searched by mistake
local SECRET = {
	["gm island"] = 0, gmisland = 0, ["gm isle"] = 0, ["gm islands"] = 0, devland = 0,
	banhammer = -1, ["ban hammer"] = -1, banned = -1, ["legendary vendor"] = -1, ["gm vendor"] = -1,
	grizzlebeard = -1,
	["gm ticket"] = -3, gmticket = -3, ticketmaster = -3,
	["game master"] = -5, sleepytime = -5,
	gms = -6, outtalunch = -6,
	["sword of a thousand truths"] = -16, ["thousand truths"] = -16, truthkeeper = -16,
	["chicken pantz"] = -17, pantz = -17, birdfeed = -17, ["bird feed"] = -17, birdseed = -17,
}
local gmSpot                      -- where it is this time (again: the same, not somewhere new)

-- the first time this character finds it: an achievement (of sorts), once
local function GmFound()
	local who = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
	ns.db.gmFound = ns.db.gmFound or {}
	if ns.db.gmFound[who] then return end
	ns.db.gmFound[who] = true
	local msg = "|cffffff00You have earned the achievement |cffffd100[You Weren't Supposed To Be Here]|r!|r"
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) end
	pcall(PlaySound, 888)          -- (the level-up fanfare)
end

-- npc: one of its people to go to (or 0: the island); status: what to say there
local function GmIsland(query, source, npc, status)
	if source == nil then SetStatus(nil) return end
	if source ~= "again" or not gmSpot then
		local ui, x, y = ns.Pins.IslandSpot()
		gmSpot = { ui = ui, x = x, y = y }
	end
	HideList()
	ns.Pins.Clear()
	SetNear(nil)
	current, pending, lastTyped = query, nil, nil
	LightQuick(nil)
	ns.Pins.ShowIsland(gmSpot.ui, gmSpot.x, gmSpot.y)
	local ui, x, y, name = gmSpot.ui, gmSpot.x, gmSpot.y, nil
	if npc and npc ~= 0 then
		local nu, nx, ny, nn = ns.Pins.IslandNpc(npc)
		if nu then ui, x, y, name = nu, nx, ny, nn end
	end
	if source ~= "again" then
		UI.GoToMap(ui, x, y, name and 8 or 4)
		GmFound()
	end
	SetStatus(status or (name and (name .. ", GM Island.")) or "GM Island. You're not supposed to be here.",
		1, 0.82, 0.1)
	LightSearch()
end

function UI.Run(query, source)
	query = Plain(query)
	if liveTimer then liveTimer:Cancel() liveTimer = nil end
	-- ("preview": a row of the drop-down looked at. Shown as if typed, the map going to it, the
	-- list left up; nothing kept. Anything else is a search of its own: no look to undo)
	local preview = source == "preview"
	if preview then source = nil elseif source ~= "again" then previewing = false end
	local fromMini = source == "mini"
	if fromMini then source = "quick" end
	query = strtrim(query or "")
	if query == "" then UI.Clear() return end
	local secret = SECRET[query:lower()]
	if secret and source ~= "quick" and ns.Pins.Available() then GmIsland(query, source, secret) return end
	-- a place's name: the map goes there (as it's typed, only once Enter is pressed: the map
	-- shouldn't jump about while you type). A town is marked too
	-- (or with its filler off: "how do i get to ratchet")
	local place = source ~= "quick" and (ns.Search.Place(query) or ns.Search.Place(ns.Search.StripFiller(query) or ""))
	if place then
		if source == nil then
			SetStatus(L["Press Enter to go to %s"]:format(place.name), 0.6, 1, 0.6)
			if preview then
				local at = place.points and place.points[1]
				if at then UI.GoToMap(at.ui, at.x, at.y, nil, true) else UI.GoToMap(place.id, nil, nil, nil, true) end
			end
			return
		end
		if place.points then
			if ns.Pins.Available() then ShowSpots(place, query, source) return end
		elseif source ~= "again" then
			GoPlace(place, query)
			return
		end
	end
	-- a farming search ("copper farm", "peacebloom route"): the loops for it, to pick one
	local farmThing, farmKind
	if source ~= "quick" and ns.Farm then farmThing, farmKind = ns.Farm.Parse(query) end
	-- (a list of farms, not worked out yet, takes a moment: not as you type, and on Enter after a
	-- word that it's coming)
	local slow = farmThing and ns.Index.done and ns.Pins.Available() and ns.Farm.Slow and ns.Farm.Slow(farmThing, farmKind)
	if slow and source == nil then
		SetStatus(L["Press Enter for farming loops: %s"]:format(slow), 0.6, 1, 0.6)
		return
	end
	-- (being worked out now, over the frames: Enter again waits with it)
	if slow and slowGo == query and ns.Farm.Working and ns.Farm.Working(farmThing, farmKind) then return end
	if slow and source ~= "again" and slowGo ~= query then
		slowGo = query
		SetStatus(L["Working out the farms: %s"]:format(slow), 0.6, 1, 0.6)
		if ns.Farm.Work then
			-- (a little each frame, the game going on; then shown, if it's still what's asked for)
			local text = L["Working out the farms: %s"]:format(slow)
			SetStatus(text .. "  0%", 0.6, 1, 0.6, true, 0)
			ns.Farm.Work(farmThing, farmKind, function()
				if slowGo ~= query then return end
				UI.Run(query, source)
				slowGo = nil
			end, function(frac)
				-- (how far it's got: the bar under the search box, as Questie's data is read by)
				if slowGo == query then SetStatus(("%s  %d%%"):format(text, frac * 100), 0.6, 1, 0.6, true, frac) end
			end)
		else
			C_Timer.After(0.05, function()
				if slowGo == query then UI.Run(query, source) end
				slowGo = nil
			end)
		end
		return
	end
	if farmThing and ns.Index.done and ns.Pins.Available() then
		local opts, title, nodes = ns.Farm.Options(farmThing, farmKind)
		-- (a list of farms just worked out: every loop of every thing in it, for a row of each.
		-- What that let go, tens of MB, swept up over the next few seconds, not left for the
		-- game to get round to in its own time)
		if slow and ns.Sweep then ns.Sweep() end
		if opts then
			if source == "again" then
				local o = farmShown and farmShown.query == query and farmShown.o or opts[1]
				FarmShow(o, title, nodes, query, true)
				return
			end
			if source == nil then
				SetStatus(L["Press Enter for farming loops: %s"]:format(title), 0.6, 1, 0.6)
				if preview then FarmShow(opts[1], title, nodes, query, false, true) end
				return
			end
			ShowFarm(query, opts, title, nodes)
			return
		end
	end
	if source and source ~= "chain" then HideList() end   -- (as you type, the suggestions stay up)
	if source and source ~= "again" and source ~= "chain" then chainQuery = nil end
	if ns.Route.Preview then ns.Route.Preview(nil) end   -- (a farming loop looked at before: gone)
	LightQuick(query)
	current = query
	LightSearch()
	if not ns.Pins.Available() then
		SetStatus(L["Questie's map library isn't available."], 1, 0.4, 0.4)
		return
	end
	if not ns.Index.done then
		pending = query
		Progress(ns.Index.progress)
		return
	end
	pending = nil
	local results, msg, service, empty, within = SearchIn(query)

	-- found nothing, or only names with it in ("stranglethorn": the vendors of Stranglethorn Seed),
	-- but it's (nearly) a zone's, city's or dungeon's name ("deadmine", "shadowfang"): the place, as
	-- its whole name would be. (Before the spelling fix: "deadmine" isn't the NPC Deadmire)
	choiceRun = choiceRun + 1   -- (a newer search: an older one's choices aren't shown)
	local choices
	if (not results or (not service and not within)) and not (results and results.coords)
		and source ~= "quick" and source ~= "again" then
		local p
		p, choices = ns.Suggest.LikePlace(query, true)
		if p then
			local q = query:lower()
			for _, r in ipairs(results or {}) do
				-- (not when it's someone's name; nor a dungeon's when it's in a title, an order's or
				-- a faction's: "darkmoon" is the Faire's people)
				local e = r.entry
				if e and ((e.name and e.name:lower() == q)
					or (p.kind == "dungeon" and e.sub and e.sub:lower():find(q, 1, true))) then
					p = nil
					break
				end
				-- (nor when it's a quest's whole name: who starts it)
				if r.kind == "QUEST" and r.rank == 0 and r.quests then p = nil break end
			end
		end
		if p then
			if source == nil then
				ns.Pins.Clear()
				SetNear(nil)
				SetStatus(L["Press Enter to go to %s"]:format(p.name), 0.6, 1, 0.6)
				return
			end
			if edit then edit:SetText(p.name) end
			if p.points then ShowSpots(p, p.name, source) else GoPlace(p, p.name) end
			return
		end
		if choices and #choices > 6 then choices = nil end
	end

	-- found nothing: try it spelled right ("fishng" -> "fishing", "orgrimar" -> "orgrimmar")
	local typed, fixPlace
	if not results and empty and source ~= "again" then
		local fix, unsold = ns.Suggest.Correct(query)
		-- (spelled right, a place's name: it's the place ("orgrimar" is Orgrimmar), not a search)
		fixPlace = fix and not unsold and ns.Search.Place(fix)
		local r2, m2, s2, w2, _
		if fix and not fixPlace then r2, m2, s2, _, w2 = SearchIn(fix) end
		if r2 then results, service, typed, query, within = r2, s2, query, fix, w2
		elseif unsold and m2 then msg, empty = m2, false end   -- ("no vendor sells Mithril Casing")
	end

	if not results and source ~= "quick" and empty then
		-- (nothing real: one of GM Island's wares? Its vendor, as a real item search finds one)
		local vid, item
		if not ns.Search.InRealNames(query) then vid, item = ns.Pins.FakeItemVendor(query) end
		if vid then
			if source == nil then SetStatus(nil) return end
			GmIsland(query, source, vid, ("1 found: %s sells %s"):format(select(4, ns.Pins.IslandNpc(vid)) or "?", item.name))
			return
		end
	end
	if not results then
		-- (nothing, but a place, spelled right, or the start of one's name ("elwynn" is Elwynn
		-- Forest), or a letter or two off one ("elwyn forest"): there. As it's typed, only said)
		local p = source ~= "again" and source ~= "quick" and empty
			and (fixPlace or ns.Search.PlaceStarting(query) or ns.Suggest.ClosestPlace(query))
		-- (or as like two or more: which, to pick)
		choices = choices or (not p and source ~= "again" and source ~= "quick" and ns.Suggest.PlaceChoices(query))
		if choices and preview then
			SetStatus(L["Did you mean one of these?"], 0.6, 1, 0.6)
			return
		end
		if choices and source then
			ns.Pins.Clear()
			SetNear(nil)
			SetStatus(L["Did you mean one of these?"], 0.6, 1, 0.6)
			ShowChoices(choices)
			return
		end
		if p and source == nil then
			ns.Pins.Clear()
			SetNear(nil)
			SetStatus(L["Press Enter to go to %s"]:format(p.name), 0.6, 1, 0.6)
			return
		elseif p then
			if edit then edit:SetText(p.name) end
			if p.points then ShowSpots(p, p.name, source) else GoPlace(p, p.name) end
			return
		end
		ns.Pins.Clear()
		SetNear(nil)
		if source == "enter" then
			-- (said under the box, what's typed blinking red)
			SetStatus(nil)
			NoResults(msg)
		else
			SetStatus(msg, 1, 0.6, 0.3)
		end
		return
	end
	if source == "quick" then
		lastTyped = nil
	elseif source == "again" or source == "chain" then
		-- (unchanged; a step of a line looked at isn't a search of its own)
	elseif source then
		Remember(query)
		lastTyped = nil
	elseif not preview then
		lastTyped = query
	end
	local placed, cut, nearest, yd, maps = ns.Pins.Show(results, service, source == "again", query == ns.db.pinned or fromMini)
	SetNear(nearest)
	if source ~= "again" then UI.Focus(maps, nearest, source == nil and not preview, preview) end
	local text = (placed == 1 and L["%d found, %d spot"] or L["%d found, %d spots"]):format(#results, placed)
	if cut then text = text .. " " .. L["(first %d)"]:format(ns.db.maxPins) end
	if nearest then text = text .. " - " .. L["nearest %d yd"]:format(yd) end
	-- (an item: where it's got, by kind: who sells it, the veins or plants, the mobs' areas)
	local dz = results.drops
	if dz then
		local vendors = 0
		for _, r in ipairs(results) do if r.kind == "VENDOR" then vendors = vendors + 1 end end
		local parts = {}
		if vendors > 0 then parts[#parts + 1] = (vendors == 1 and L["sold by 1 vendor"] or L["sold by %d vendors"]:format(vendors)) end
		if dz.nodes then
			parts[#parts + 1] = L["gathered from %d spots in %s"]:format(dz.nodes, dz.zone)
				.. (dz.nodeMore > 0 and (" " .. L["(and %d other zones)"]:format(dz.nodeMore)) or "")
		end
		if dz.spots then
			parts[#parts + 1] = (dz.spots == 1 and L["dropped by mobs in %s"]:format(dz.spotZone)
				or L["dropped by mobs in %d places in %s"]:format(dz.spots, dz.spotZone))
				.. (dz.spotMore > 0 and (" " .. L["(and %d other zones)"]:format(dz.spotMore)) or "")
		end
		text = (vendors > 0 and L["%s: %s."] or L["No vendor sells %s: %s."]):format(dz.name, table.concat(parts, "; "))
		if nearest then text = text .. " - " .. L["nearest %d yd"]:format(yd) end
	end
	-- (a quest you're on: where to go for it now)
	if results.questNow then
		text = results.questNow
		if nearest then text = text .. " - " .. L["nearest %d yd"]:format(yd) end
	end
	if within and not results.coords then text = L["In %s: %s"]:format(within.name, text) end
	if results.missing and #results.missing > 0 then
		text = text .. "\n" .. L["Not on the map (in a dungeon, or offline): %s"]:format(table.concat(results.missing, ", "))
	end
	-- (your group: they move, so their markers follow them)
	if results.group then FollowGroup(query) end
	-- (found, but it's as like a few places too: those, to pick one instead)
	if choices and source and source ~= "again" and source ~= "quick" and not typed then
		text = text .. "\n" .. L["Did you mean one of these?"]
		ShowChoices(choices)
	end
	if typed then text = L["Showing \"%s\" (nothing for \"%s\")"]:format(query, typed) .. "\n" .. text end
	SetStatus(text, 0.6, 1, 0.6)
	LightSearch()
	if RefreshMini then RefreshMini() end
	-- (a quest in a line, searched or a step picked: the line in the drop-down)
	if results.chain and (source == "enter" or source == "recent" or source == "slash" or source == "chain") then
		ShowChain(results.chain)
	elseif results.choices and #results.choices > 0 and (source == "enter" or source == "recent" or source == "slash") then
		ShowGoTo(results.choices)
	end
end

-- is map `ui` the map `top`, or inside it?
local function Inside(top, ui)
	local id, guard = ui, 0
	while id and id > 0 and guard < 12 do
		if id == top then return true end
		local info = C_Map.GetMapInfo(id)
		id = info and info.parentMapID
		guard = guard + 1
	end
	return false
end

--- the map moved to where the results are: their zone when they're all in one, else (when
--- none of them is on the map shown) the nearest one's zone. As you type, only the first:
--- the map shouldn't jump about while a search is half typed
function UI.Focus(maps, nearest, typing, quick)
	if not (ns.db.focus and maps and WorldMapFrame:IsShown()) then return end
	-- OpenMap's map: out and in to the nearest result, as to a place (not as it's typed: the map
	-- shouldn't sweep about while a search is half typed)
	local stitched = UI.Stitched()
	if stitched then
		if typing then return end
		if nearest and nearest.ui then
			UI.GoToMap(nearest.ui, nearest.x / 100, nearest.y / 100, RESULT_ZOOM, quick)
			return
		end
	end
	local list = {}
	for ui in pairs(maps) do list[#list + 1] = ui end
	if #list == 0 then return end
	local shown = WorldMapFrame:GetMapID()
	local target
	if #list == 1 then
		target = list[1]
	elseif not typing then
		for _, ui in ipairs(list) do
			if shown and Inside(shown, ui) then return end   -- (some are on the map already)
		end
		target = nearest and nearest.ui or list[1]
	end
	if target and target ~= shown then
		if stitched then UI.GoToMap(target, nil, nil, nil, quick) else WorldMapFrame:SetMapID(target) end
	end
end

--- a waypoint to a match (the nearest button, or a click on any marker)
function UI.TakeMeThere(d)
	-- (GM Island's: no waypoint goes there)
	if d.island then
		SetStatus(ns.Pins.WaypointGag(), 1, 0.82, 0.1)
		return
	end
	-- (further than riding straight there: the quickest way, step by step)
	if ns.Route then
		local ok, r = ns.Route.Start(d)
		if ok then
			SetStatus(L["Route to %s: about %s"]:format(d.name, ns.Route.Minutes(r.total)), 0.6, 1, 0.6)
			return
		end
	end
	ns.Pins.SetWaypoint(d)
	local far = d.island and (" - " .. ns.Pins.DistanceGag()) or Yards(ns.Pins.Distance(d))
	SetStatus(L["Taking you to %s, %s%s"]:format(d.name, d.place or ns.ZoneName(d.ui), far), 0.6, 1, 0.6)
end

--- search (the map opened for it), and be taken to the nearest match: the repair reminder
function UI.GoNearest(query)
	if not WorldMapFrame:IsShown() then
		if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
	end
	if edit then edit:SetText(query) end
	UI.Run(query, "quick")
	local d = ns.Index.done and ns.Pins.Nearest()
	if d then
		SetNear(d)
		UI.TakeMeThere(d)
	elseif ns.Index.done then
		SetStatus(L["No %s on your continent."]:format(query), 1, 0.6, 0.3)
	end
end

--- the search on the map now, again (a setting changed, or the map moved to another zone)
function UI.Again()
	if current and bar and bar:IsVisible() then UI.Run(current, "again") end
end

-- the last search typed, into the recents (once you've stopped typing it)
local function KeepTyped()
	if lastTyped then Remember(lastTyped) lastTyped = nil end
end

-- a row of the drop-down picked: search for it
function Pick(d)
	if d.kind == "empty" or d.kind == "none" then return end
	previewing, lookedAt = false, nil
	previewRun = previewRun + 1
	if d.kind == "addfav" then
		ToggleFavorite(d.text)
		ShowFavorites()
		return
	end
	if d.kind == "manage" then
		HideList()
		edit:ClearFocus()
		ns.Settings.Open("favs")
		return
	end
	-- (a step of a quest line: shown, the line left up to pick another)
	if d.kind == "chain" then
		chainQuery = d.text
		UI.Run(d.text, "chain")
		return
	end
	-- (a farming loop: shown, and ridden round until it's stopped)
	-- (a row of a list of farms, "cloth farm"'s Linen Cloth: its own loops, zone by zone, to pick from)
	if d.kind == "farm" and d.farm and d.farm.more then
		previewRun = previewRun + 1
		edit:SetText(d.farm.more)
		UI.Run(d.farm.more, "enter")
		return
	end
	if d.kind == "farm" then
		HideList()
		edit:ClearFocus()
		previewRun = previewRun + 1   -- (a look still to come: not now)
		if not (farmShown and farmShown.o == d.farm) then FarmShow(d.farm, d.title, d.nodes, d.text) end
		if ns.Farm.Start(d.farm, d.title) then
			SetStatus(L["Farming %s in %s: follow the green loop"]:format(d.title, d.farm.zone), 0.6, 1, 0.6)
		end
		return
	end
	HideList()
	edit:SetText(d.text)
	edit:ClearFocus()
	UI.Run(d.text, (d.kind == "recent" or d.kind == "fav" or d.kind == "pinned") and "recent" or "enter")
end

-- the search box back to empty (markers left alone)
local function ResetSearch()
	if liveTimer then liveTimer:Cancel() liveTimer = nil end
	KeepTyped()
	pending = nil
	if edit then
		edit:SetText("")
		edit:ClearFocus()
	end
	HideList()
	LightQuick(nil)
	SetStatus(nil)
end

function UI.Clear()
	if ns.Route.Preview then ns.Route.Preview(nil) end
	-- (clearing the pinned search unpins it)
	if ns.db.pinned and current == ns.db.pinned then
		ns.db.pinned = nil
		ns.Print(L["unpinned; the markers go when the map closes from now on"])
	end
	current = nil
	ns.Pins.Clear()
	SetNear(nil)
	ResetSearch()
	LightSearch()
	if RefreshMini then RefreshMini() end
end

--- a route's stopped (a farming loop's, when loop): its veins and herbs, kept past the map's
--- closing, go now if the map's still closed
function UI.RouteStopped(loop)
	if loop and ns.Pins.HasFarm() and ns.db.pinned ~= current
		and not (WorldMapFrame and WorldMapFrame:IsShown()) then
		UI.Clear()
	end
end

-- pin a starred search (search it now, and keep it after the map closes), or unpin it
function TogglePin(query)
	if ns.db.pinned == query then
		ns.db.pinned = nil
		RefreshList()
		LightSearch()
		SetStatus(L["Unpinned \"%s\": it goes when the map closes."]:format(query), 1, 0.82, 0.1)
		return
	end
	ns.db.pinned = query
	edit:SetText(query)
	edit:ClearFocus()
	UI.Run(query, "recent")
	LightSearch()
	SetStatus(L["Pinned \"%s\": it stays on the map and minimap until you unpin it."]:format(query), 0.6, 1, 0.6)
end

function UI.TogglePin(query) TogglePin(query) end

-- the pinned search back on the map (after the map closes, at login, in a new zone)
local function ShowPinned()
	local q = ns.db.pinned
	if q and ns.Index.done then
		if edit then edit:SetText("") end
		UI.Run(q, "again")
	end
end

function UI.SearchFromSlash(query)
	if not WorldMapFrame:IsShown() then
		if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
	end
	if edit then edit:SetText(query) end
	UI.Run(query, "slash")
end

--- a search asked for from a marker on the map (right-click on a quest item's: its quest): as
--- if typed and entered
function UI.SearchFromPin(query)
	if edit then edit:SetText(query) end
	UI.Run(query, "enter")
end

function UI.OnIndexProgress(progress)
	if pending then Progress(progress) end
end

function UI.OnIndexed()
	if pending then UI.Run(pending) elseif ns.db.pinned and not current then ShowPinned() end
end

--------------------------------------------------------------------------------
-- Placing the bar: at the right end of the nav bar, left of the map's tracking
-- (filter) button when that sits on the same row
--------------------------------------------------------------------------------

local function TrackingButton()
	local mixin = _G.WorldMapTrackingOptionsButtonMixin
	if not mixin then return end
	for _, f in ipairs(WorldMapFrame.overlayFrames or {}) do
		if f.OnLoad == mixin.OnLoad then return f end
	end
end

-- the bar's width: the search button, the quick buttons, the nearest and More buttons
local function BarWidth()
	return (BUTTON + 2) * (#shown + 3) + 6
end

-- Where the bar sits (Options, "Search bar"): "top", across the map's top bar over the
-- breadcrumbs, as it always has; "bottom", along the bottom of the map; "custom", where you
-- dragged it (move mode). Off the top bar, the search box sits left of the bar, and the list,
-- the count and More open upwards when the bar's in the lower half of the map
local STRIP_WIDTH = 260
local mover   -- move mode: over the bar and the box, to drag them

local function MapArea() return WorldMapFrame.ScrollContainer or WorldMapFrame end

--- does what hangs off the bar (the list, the count, More, the settings) open upwards?
function UI.Up()
	local pos = ns.db.barPos or "top"
	if pos == "bottom" then return true end
	if pos ~= "custom" or not bar then return false end
	local area = MapArea()
	local _, by = bar:GetCenter()
	local _, ay = area:GetCenter()
	if not (by and ay) then return false end
	return by * bar:GetEffectiveScale() < ay * area:GetEffectiveScale()
end

-- the bar and the box onto a frame: the nav bar (top), or the map itself
local function Mount(parent, floating)
	if bar:GetParent() ~= parent then bar:SetParent(parent) end
	if strip and strip:GetParent() ~= parent then strip:SetParent(parent) end
	local base = floating and MapArea():GetFrameLevel() + 100 or parent:GetFrameLevel()
	bar:SetFrameLevel(base + 10)
	if strip then
		strip:SetFrameLevel(base + 50)
		strip:ClearAllPoints()
		if floating then
			strip:SetWidth(STRIP_WIDTH)
		else
			strip:SetPoint("LEFT", parent, "LEFT", 2, 0)
		end
		strip:SetPoint("RIGHT", searchBtn, "LEFT", -4, 0)
	end
end

-- what hangs off the bar, opening down (or up)
function Hang()
	local up = UI.Up()
	if statusBox then
		statusBox:ClearAllPoints()
		local open = strip and strip:IsShown()
		-- (the pill's as wide as its words, up to the box's width (wrapped past that); its fill,
		-- while the data's read, as far along as that is)
		local maxW = open and (STRIP_WIDTH + 60) or 320
		status:SetWidth(maxW)
		local w = math.min(status:GetStringWidth() + 1, maxW)
		status:SetWidth(w)
		statusBox:SetSize(w + 14, status:GetStringHeight() + 9)
		statusBox.fill:SetShown(statusBox.progress ~= nil)
		if statusBox.progress then statusBox.fill:SetWidth(math.max(1, (w + 12) * statusBox.progress)) end
		if open then
			-- (the search box open: under it, left-aligned; under its suggestions while they're up,
			-- so the two don't sit on each other)
			local over = (list and list:IsShown()) and list or strip
			if up then statusBox:SetPoint("BOTTOMLEFT", over, "TOPLEFT", over == list and 0 or 2, 4)
			else statusBox:SetPoint("TOPLEFT", over, "BOTTOMLEFT", over == list and 0 or 2, -4) end
		else
			if up then statusBox:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 4)
			else statusBox:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -4) end
		end
	end
	if list and edit then
		list:ClearAllPoints()
		if up then list:SetPoint("BOTTOMLEFT", edit, "TOPLEFT", -8, 2)
		else list:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -8, -2) end
	end
end

function UI.Place()
	if not bar then return end
	bar:ClearAllPoints()
	bar:SetWidth(BarWidth())
	local nav = WorldMapFrame.NavBar
	local pos = ns.db.barPos or "top"
	if pos ~= "top" or not nav then
		local area = MapArea()
		Mount(WorldMapFrame, true)
		local at = ns.db.barAt
		if pos == "custom" and at then
			-- (kept as a share of the map's width and height: it stays put as the map's resized)
			local w, h = area:GetWidth(), area:GetHeight()
			local k = area:GetEffectiveScale() / bar:GetEffectiveScale()
			bar:SetPoint("TOPRIGHT", area, "TOPLEFT", at[1] * w * k, -at[2] * h * k)
		elseif pos == "top" then
			bar:SetPoint("TOPRIGHT", area, "TOPRIGHT", -40, -6)
		else
			bar:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -8, 8)
		end
		Hang()
		return
	end
	Mount(nav, false)
	Hang()
	local track = TrackingButton()
	local nt, nb = nav:GetTop(), nav:GetBottom()
	if track and track:IsShown() and nt and nb then
		local _, ty = track:GetCenter()
		if ty and ty <= nt and ty >= nb then
			bar:SetPoint("RIGHT", track, "LEFT", -6, 0)
			return
		end
	end
	bar:SetPoint("RIGHT", nav, "RIGHT", -6, 0)
end

--------------------------------------------------------------------------------
-- The search box: a strip across the top bar, over the breadcrumbs, opened by the search
-- button and closed again once you're done (out of the box, the list gone)
--------------------------------------------------------------------------------

-- the search closed: the strip, the box's focus and the list (what's on the map stays)
local function CloseSearch()
	if not strip then return end
	if edit then edit:ClearFocus() end
	HideList()
	strip:Hide()
end

local function OpenSearch()
	if not strip then return end
	strip:Show()
	LightSearch()
	edit:SetFocus()
	edit:HighlightText()
end

--- the search open whenever the map opens, or not (the settings); the map open now follows it
function UI.SetSearchOpen(on)
	ns.db.searchOpen = on and true or false
	if not (strip and bar and bar:IsVisible()) then return end
	if on and not strip:IsShown() then
		strip:Show()
		LightSearch()
	elseif not on and strip:IsShown() and strtrim(edit:GetText() or "") == "" then
		CloseSearch()
	end
end

-- (the strip no longer closes by itself once you're done with it: it stays open until the map
-- closes, its X is clicked, or the search button is clicked again. Kept as a no-op for the
-- places that call it)
function SyncSearch() end

--- the minimap button: the map open with the search box ready to type in. Again with both
--- open, the map closes
local quickOpened   -- the minimap button opened the search on this showing of the map
local RELEASE_AFTER = 20   -- seconds after the map closes that the suggestions' vocabulary is let go
local releaseTimer

function UI.QuickSearch()
	UI.Create()
	if WorldMapFrame:IsShown() then
		-- (a second click closes the map. The search being open isn't enough to tell: it can be
		-- open from the start, and then the first click is to type in it)
		if quickOpened and strip and strip:IsShown() then
			if ToggleWorldMap then ToggleWorldMap() else HideUIPanel(WorldMapFrame) end
		else
			OpenSearch()
			quickOpened = true
		end
		return
	end
	if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
	-- (once the map has laid its bar out)
	C_Timer.After(0.05, function()
		if WorldMapFrame:IsShown() then
			OpenSearch()
			quickOpened = true
		end
	end)
end


local function MakeStrip(nav)
	local f = CreateFrame("Frame", nil, nav or bar)
	-- (well over the breadcrumb buttons; the box and its clear button, made after, sit higher still)
	f:SetFrameLevel((nav or bar):GetFrameLevel() + 50)
	f:SetHeight(BUTTON + 2)
	if nav then
		f:SetPoint("LEFT", nav, "LEFT", 2, 0)
	else
		f:SetWidth(260)
	end
	f:SetPoint("RIGHT", searchBtn, "LEFT", -4, 0)
	f:EnableMouse(true)
	-- (moving off it, done with it: it closes)
	f:SetScript("OnLeave", function() C_Timer.After(0, SyncSearch) end)
	-- the star at its right end: your favourites, to pin one or put one on the bar
	local favs = CreateFrame("Button", nil, f)
	favs:SetSize(18, 18)
	favs:SetPoint("RIGHT", -4, 0)
	local ft = favs:CreateTexture(nil, "ARTWORK")
	ft:SetAllPoints()
	if ft:SetTexture("Interface\\AddOns\\Questie\\Icons\\fav.tga") == false then
		ft:SetTexture("Interface\\Common\\ReputationStar")
		ft:SetTexCoord(0, 0.5, 0, 0.5)
	end
	favs:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	favs:SetScript("OnClick", function()
		GameTooltip:Hide()
		if list:IsShown() and listMode == "favs" then HideList() else ShowFavorites() end
	end)
	favs:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["Favourites"], 1, 0.82, 0.1)
		GameTooltip:AddLine(L["Star the search on the map, pin a favourite to keep it after the map closes, or put one on the bar as a button."], 1, 1, 1, true)
		if ns.db.pinned then GameTooltip:AddLine(L["Pinned: \"%s\""]:format(ns.db.pinned), 0.6, 0.8, 1) end
		GameTooltip:Show()
	end)
	favs:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.favs = favs
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(PANEL_BG))
	local edge = f:CreateTexture(nil, "BORDER")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetHeight(1)
	edge:SetColorTexture(unpack(PANEL_EDGE))
	-- (EUI: its flat panel in place of the dark strip and its gold edge)
	ns.OnSkin(function(S)
		bg:Hide()
		edge:Hide()
		S.Panel(f)
	end)
	f:Hide()
	return f
end

--------------------------------------------------------------------------------
-- More: the quick buttons past the first 5, then the settings
--------------------------------------------------------------------------------

local MENU_W, MENU_ROW = 180, 20

--- the quick buttons you picked past the bar's, this character's
function UI.ExtraSpecs()
	local out, n = {}, 0
	local hunter = IsHunter()
	for _, key in ipairs(ns.db.buttons) do
		local spec = UI.Spec(key)
		if spec and (hunter or not spec.hunter) then
			n = n + 1
			if n > UI.MAX_BUTTONS then out[#out + 1] = spec end
		end
	end
	return out
end

local function MenuRow(i)
	menu.rows = menu.rows or {}
	local r = menu.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, menu)
	r:SetSize(MENU_W - 12, MENU_ROW)
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	local icon = r:CreateTexture(nil, "ARTWORK")
	icon:SetSize(MENU_ROW - 4, MENU_ROW - 4)
	icon:SetPoint("LEFT", 4, 0)
	r.icon = icon
	local glow = r:CreateTexture(nil, "BACKGROUND")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 0.82, 0.1, 0.25)
	r.glow = glow
	local t = ns.Text(r, "GameFontHighlightSmall")
	t:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	t:SetPoint("RIGHT", -4, 0)
	t:SetJustifyH("LEFT")
	r.text = t
	ns.SkinText(t)
	r:SetScript("OnClick", function(self)
		menu:Hide()
		if self.action then self.action() end
	end)
	menu.rows[i] = r
	return r
end

local function MakeMenu()
	local ok, f = pcall(CreateFrame, "Frame", "MapSeekMore", bar, "BackdropTemplate")
	if not ok or not f then f = CreateFrame("Frame", "MapSeekMore", bar) end
	f:SetFrameStrata("DIALOG")
	f:SetWidth(MENU_W)
	f:EnableMouse(true)
	Flat(f)
	-- (on a frame of its own: EUI's panel fades the menu's own textures)
	local lf = CreateFrame("Frame", nil, f)
	lf:SetAllPoints()
	f.line = lf:CreateTexture(nil, "ARTWORK")
	f.line:SetHeight(1)
	f.line:SetColorTexture(1, 1, 1, 0.15)
	-- (a click anywhere else closes it)
	f:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
	f:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
	f:SetScript("OnEvent", function(self)
		if not (self:IsMouseOver() or more:IsMouseOver()) then self:Hide() end
	end)
	f:Hide()
	return f
end

local function QuickPress(query)
	if lit == query then UI.Clear() return end   -- pressed again: off
	KeepTyped()
	edit:SetText(query)
	edit:ClearFocus()
	UI.Run(query, "quick")
end

-- right-click on a quick button: pin its search (on the map and minimap until unpinned), or,
-- pinned already, unpin it and take it off the map
local function QuickPin(query)
	if ns.db.pinned == query then
		TogglePin(query)
		if current == query then UI.Clear() end
		return
	end
	KeepTyped()
	TogglePin(query)   -- (runs it, which lights the button)
end

--- a starred search's icon picked from a menu of them all
function UI.IconMenu(owner, query)
	local items = { { title = L["Its button's icon"] } }
	for _, k in ipairs(UI.ICONS) do
		-- (named for the quick search with that icon)
		local name = k == "SEARCH" and L["Search"] or k == "CLASS" and L["Class trainer"] or ""
		for _, spec in ipairs(CATALOG) do if spec.icon == k then name = spec.label break end end
		items[#items + 1] = { text = name, look = ns.LOOKS[k], radio = true,
			checked = function() return (ns.db.favIcons[query] or "SEARCH") == k end,
			func = function()
				ns.db.favIcons[query] = k
				UI.Layout()
				if ns.Settings.Refresh then ns.Settings.Refresh() end
			end }
	end
	return ns.OpenMenu(owner, items)
end

-- right-click on a quick button: a menu (pin it, the minimap button finds it, its icon, off the
-- bar). Without a menu of the game's: pin it, as before
local function QuickMenu(b)
	local key, query = b.key, b.query
	if not key then return end
	local pinned = ns.db.pinned == query
	local items = {
		{ title = b.label },
		{ text = pinned and L["Unpin it"] or L["Pin it"], func = function() QuickPin(query) end },
	}
	if b.fav then
		items[#items + 1] = { text = L["Change its icon..."], func = function()
			C_Timer.After(0, function() UI.IconMenu(b, query) end)
		end }
	end
	items[#items + 1] = { text = L["Take it off the bar"], func = function()
		for i = #ns.db.buttons, 1, -1 do
			if ns.db.buttons[i] == key then table.remove(ns.db.buttons, i) end
		end
		UI.Layout()
		if ns.Settings.Refresh then ns.Settings.Refresh() end
	end }
	if not ns.OpenMenu(b, items) then QuickPin(query) end
end

local function ToggleMenu()
	menu = menu or MakeMenu()
	if menu:IsShown() then menu:Hide() return end
	HideList()
	local y, i = -6, 0
	for _, spec in ipairs(UI.ExtraSpecs()) do
		i = i + 1
		local r = MenuRow(i)
		ns.SetLook(r.icon, ns.LOOKS[spec.icon])
		r.text:SetText(spec.label)
		r.glow:SetShown(lit == spec.query)
		r.action = function() QuickPress(spec.query) end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 6, y)
		r:Show()
		y = y - MENU_ROW
	end
	if i > 0 then
		menu.line:ClearAllPoints()
		menu.line:SetPoint("TOPLEFT", 8, y - 3)
		menu.line:SetPoint("TOPRIGHT", -8, y - 3)
		menu.line:Show()
		y = y - 7
	else
		menu.line:Hide()
	end
	-- (the farm lists' window)
	if ns.FarmList and ns.FarmList.Toggle then
		i = i + 1
		local fr = MenuRow(i)
		fr.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
		fr.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		fr.text:SetText(L["Farm list"])
		fr.glow:SetShown(ns.FarmList.Running())
		fr.action = function() ns.FarmList.Toggle() end
		fr:ClearAllPoints()
		fr:SetPoint("TOPLEFT", 6, y)
		fr:Show()
		y = y - MENU_ROW
	end
	i = i + 1
	local r = MenuRow(i)
	r.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.text:SetText(L["Settings"])
	r.glow:Hide()
	r.action = function() ns.Settings.Toggle() end
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", 6, y)
	r:Show()
	y = y - MENU_ROW
	for j = i + 1, #menu.rows do menu.rows[j]:Hide() end
	menu:SetHeight(-y + 6)
	menu:ClearAllPoints()
	if UI.Up() then menu:SetPoint("BOTTOMRIGHT", more, "TOPRIGHT", 0, 2)
	else menu:SetPoint("TOPRIGHT", more, "BOTTOMRIGHT", 0, -2) end
	menu:Show()
end

--------------------------------------------------------------------------------
-- Reordering: drag a button along its row, drop it where it should go
--------------------------------------------------------------------------------

--- b follows the mouse while dragged; dropped, onDrop(b, index) gets the place in row() (the
--- buttons in order, b among them) it was dropped at
function UI.Draggable(b, row, onDrop)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self.strata = self:GetFrameStrata()
		self:SetFrameStrata("TOOLTIP")
		self:SetScript("OnUpdate", function(s)
			local x, y = GetCursorPosition()
			local sc = s:GetEffectiveScale()
			s:ClearAllPoints()
			s:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc, y / sc)
		end)
	end)
	b:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:SetFrameStrata(self.strata or "HIGH")
		self.dropped = GetTime()   -- (the click that ends a drag isn't a click)
		local x = GetCursorPosition()
		local to = 1
		for _, o in ipairs(row()) do
			if o ~= self then
				local cx = o:GetCenter()
				if cx and cx * o:GetEffectiveScale() < x then to = to + 1 end
			end
		end
		onDrop(self, to)
	end)
end

--- true just after a drag ended on b (its click is the end of the drag)
function UI.JustDropped(b)
	return b.dropped and GetTime() - b.dropped < 0.25
end

--- the keys of every quick button you picked that this character can have, in order (the
--- first MAX_BUTTONS are on the bar, the rest under More)
function UI.PickedKeys()
	local keys, hunter = {}, IsHunter()
	for _, key in ipairs(ns.db.buttons) do
		local spec = UI.Spec(key)
		if spec and (hunter or not spec.hunter) then keys[#keys + 1] = key end
	end
	return keys
end

--- the keys of the quick buttons on the bar, in order
function UI.ShownKeys()
	local keys = {}
	for i, s in ipairs(shown) do keys[i] = s.key end
	return keys
end

--- move a quick button to place `to` on the bar. (Saved buttons this character can't have,
--- a hunter's on another character, keep their places.)
function UI.MoveButton(key, to)
	local keys = UI.ShownKeys()
	local from = tIndexOf and tIndexOf(keys, key)
	if not from then
		for i, k in ipairs(keys) do if k == key then from = i end end
	end
	if not from then return end
	table.remove(keys, from)
	table.insert(keys, math.max(1, math.min(to, #keys + 1)), key)
	local on = {}
	for _, k in ipairs(keys) do on[k] = true end
	local j = 0
	for i, k in ipairs(ns.db.buttons) do
		if on[k] then
			j = j + 1
			ns.db.buttons[i] = keys[j]
		end
	end
	UI.Layout()
	if ns.Settings.Refresh then ns.Settings.Refresh() end
end

--------------------------------------------------------------------------------
-- Building it
--------------------------------------------------------------------------------

local function MakeEdit(parent)
	local ok, e = pcall(CreateFrame, "EditBox", "MapSeekBox", parent, "SearchBoxTemplate")
	if not ok or not e then
		e = CreateFrame("EditBox", "MapSeekBox", parent, "InputBoxTemplate")
	end
	e:SetAutoFocus(false)
	e:SetHeight(20)
	ns.UseFont(e)
	if e.Instructions then ns.UseFont(e.Instructions) end
	if e.SetAltArrowKeyMode then e:SetAltArrowKeyMode(false) end   -- (the arrow keys move in the list)
	if e.Instructions then e.Instructions:SetText(L["Search NPCs, items, skill books, mailboxes..."]) end
	-- (quiet help: the grey words in the empty box name a search to try, another each time the
	-- map's opened or the box is emptied. The searches themselves are typed as they're shown, so
	-- they aren't translated)
	local TRY = { "iron ore farm", "first aid 225", "quests", "tin farm", "where to train riding",
		"deadmines quests", "flight master", "linen cloth", "hillsbrad farm", "timbermaw rep", "water",
		"rares", "class quests", "mc attunement", "artisan tailoring", "graveyard", "repair", "mailbox" }
	local tryAt = math.random(#TRY)
	if e.Instructions then
		local first = true
		local function Another()
			if first then first = false return end   -- (the first time: what the box is, plainly)
			tryAt = tryAt % #TRY + 1
			e.Instructions:SetText(L["Search, or try \"%s\""]:format(TRY[tryAt]))
		end
		e:HookScript("OnShow", Another)
		e:HookScript("OnEditFocusLost", function(self) if strtrim(self:GetText() or "") == "" then Another() end end)
	end
	-- the X: our own, in place of the template's. The template's shows only while there's text
	-- or the box has the focus, so with the box empty it hid as the click on it took the focus,
	-- and the click went nowhere. Ours is there all the while the search is open
	local tx = e.clearButton or e.ClearButton
	if tx then
		tx:Hide()
		tx:HookScript("OnShow", tx.Hide)
	end
	local x = CreateFrame("Button", nil, e)
	x:SetSize(16, 16)
	x:SetPoint("RIGHT", -3, 0)
	x:SetFrameLevel(e:GetFrameLevel() + 2)
	local xt = x:CreateTexture(nil, "ARTWORK")
	xt:SetAllPoints()
	xt:SetTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
	xt:SetAlpha(0.5)
	x:SetScript("OnClick", function()
		-- (the search open with the map, the setting: it stays, only cleared. The search button
		-- hides it)
		if ns.db.searchOpen then
			e:ClearFocus()
			HideList()
		else
			CloseSearch()
		end
		-- (cleared too, markers and all: what's typed, or a search still on the map; but not a
		-- pinned search left on the map with nothing typed, so that stays)
		if strtrim(e:GetText() or "") ~= "" or (current and current ~= ns.db.pinned) then UI.Clear() end
	end)
	x:SetScript("OnEnter", function(self)
		xt:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		if ns.db.searchOpen then
			GameTooltip:AddLine(L["Clear"], 1, 0.82, 0.1)
			GameTooltip:AddLine(L["Empties the search and takes the markers off the map"], 1, 1, 1, true)
		else
			GameTooltip:AddLine(L["Clear and close"], 1, 0.82, 0.1)
			GameTooltip:AddLine(L["Takes the markers off the map and closes the search"], 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	x:SetScript("OnLeave", function()
		xt:SetAlpha(0.5)
		GameTooltip:Hide()
	end)
	e.closeX = x
	return e
end

-- a square icon button in the bar's style (the quick buttons and the settings button)
local function MakeSquare(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(BUTTON, BUTTON)
	local edge = b:CreateTexture(nil, "BACKGROUND", nil, -1)
	edge:SetAllPoints()
	edge:SetColorTexture(unpack(PANEL_EDGE))
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(unpack(PANEL_BG))
	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", 3, -3)
	tex:SetPoint("BOTTOMRIGHT", -3, 3)
	b.icon = tex
	ns.OnSkin(function() edge:Hide() end)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

--------------------------------------------------------------------------------
-- The minimap button's quick searches: a click on it opens a column of up to 6 of your
-- favourites (picked in the settings' Favourites tab). A click on one finds it on the minimap,
-- the map staying closed (open it for the rest); a click on it again clears it
--------------------------------------------------------------------------------

UI.MINI_MAX = 6
local mini, miniButtons = nil, {}
local MINI_BUTTON = 26

--- the minimap button's searches: { spec, ... } (the favourites picked, still favourites)
function UI.MiniSpecs()
	local out = {}
	for _, q in ipairs(ns.db.minimapButtons or {}) do
		if IsFavorite(q) and #out < UI.MINI_MAX then
			local spec = UI.FavSpec(q)
			if spec then out[#out + 1] = spec end
		end
	end
	return out
end

function UI.OnMini(query)
	for _, q in ipairs(ns.db.minimapButtons or {}) do if q == query then return true end end
	return false
end

--- a favourite on the minimap button, or off it. Returns false when there's no room
function UI.ToggleMini(query)
	local list = ns.db.minimapButtons
	for i = #list, 1, -1 do
		if list[i] == query then table.remove(list, i) RefreshMini() return true end
	end
	if #list >= UI.MINI_MAX then return false end
	list[#list + 1] = query
	RefreshMini()
	return true
end

--- the first time: the bar's quick buttons, up to 6
function UI.SeedMini()
	local db = ns.db
	if db.miniSeeded then return end
	db.miniSeeded = true
	db.minimapButtons = db.minimapButtons or {}
	if #db.minimapButtons > 0 then return end
	for _, key in ipairs(db.buttons) do
		local spec = UI.Spec(key)
		if spec and #db.minimapButtons < UI.MINI_MAX and IsFavorite(spec.query) then
			db.minimapButtons[#db.minimapButtons + 1] = spec.query
		end
	end
end

local function MiniAnchor()
	local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
	local b = DBI and DBI.GetMinimapButton and DBI:GetMinimapButton("MapSeek")
	return b or Minimap
end

function RefreshMini()
	if not (mini and mini:IsShown()) then return end
	local specs = UI.MiniSpecs()
	for i, b in ipairs(miniButtons) do
		local spec = specs[i]
		b.spec = spec
		if spec then
			ns.SetLook(b.icon, ns.LOOKS[spec.icon] or ns.LOOKS.SEARCH)
			b.lit:SetShown(current ~= nil and current == spec.query)
			b:Show()
		else
			b:Hide()
		end
	end
	-- (laid out the way it opens: a row to the left or right, a column down or up, the first
	-- nearest the button)
	local side = ns.db.minimapSide or "left"
	local n = math.max(1, #specs)
	local along = 4 + n * (MINI_BUTTON + 2) + 2
	if side == "left" or side == "right" then
		mini:SetSize(along, MINI_BUTTON + 8)
	else
		mini:SetSize(MINI_BUTTON + 8, along)
	end
	for i, b in ipairs(miniButtons) do
		b:ClearAllPoints()
		local off = 4 + (i - 1) * (MINI_BUTTON + 2)
		if side == "left" then b:SetPoint("RIGHT", mini, "RIGHT", -off, 0)
		elseif side == "right" then b:SetPoint("LEFT", mini, "LEFT", off, 0)
		elseif side == "up" then b:SetPoint("BOTTOM", mini, "BOTTOM", 0, off)
		else b:SetPoint("TOP", mini, "TOP", 0, -off) end
	end
	mini.empty:SetShown(#specs == 0)
end

local function MiniClick(b)
	local spec = b.spec
	if not spec then return end
	if current == spec.query then
		UI.Clear()
	else
		UI.Create()
		KeepTyped()
		if edit then edit:SetText(spec.query) end
		UI.Run(spec.query, "mini")
	end
	RefreshMini()
	if b:IsMouseOver() then b:GetScript("OnEnter")(b) end
end

local function MakeMini()
	if mini then return mini end
	local f = CreateFrame("Frame", "MapSeekMiniMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetFrameStrata("HIGH")
	f:SetSize(MINI_BUTTON + 8, MINI_BUTTON + 8)
	f:SetClampedToScreen(true)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		f:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
		f:SetBackdropBorderColor(1, 0.82, 0.1, 0.6)
	end
	ns.SkinPanel(f)
	f:EnableMouse(true)
	for i = 1, UI.MINI_MAX do
		local b = MakeSquare(f)
		b:SetSize(MINI_BUTTON, MINI_BUTTON)
		local glow = b:CreateTexture(nil, "OVERLAY")
		glow:SetAllPoints()
		glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		glow:SetBlendMode("ADD")
		glow:Hide()
		b.lit = glow
		b:SetScript("OnClick", function(self) MiniClick(self) end)
		b:SetScript("OnEnter", function(self)
			if not self.spec then return end
			GameTooltip:SetOwner(self, (ns.db.minimapSide == "right") and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
			GameTooltip:AddLine(self.spec.label, 1, 0.82, 0.1)
			if current == self.spec.query then
				GameTooltip:AddLine(L["Click again to clear it"], 1, 1, 1)
			else
				GameTooltip:AddLine(L["Click to find it on the minimap (the map stays closed)"], 1, 1, 1, true)
			end
			GameTooltip:Show()
		end)
		miniButtons[i] = b
	end
	local empty = ns.Text(f, "GameFontDisableSmall")
	empty:SetPoint("CENTER")
	empty:SetWidth(MINI_BUTTON + 4)
	empty:SetText("?")
	f.empty = empty
	f:SetScript("OnEnter", function(self)
		if #UI.MiniSpecs() > 0 then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Nothing picked yet: tick up to 6 favourites in the settings' Favourites tab."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- (a click anywhere else closes it)
	f:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
	f:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
	f:SetScript("OnEvent", function(self)
		if not (self:IsMouseOver() or MiniAnchor():IsMouseOver()) then self:Hide() end
	end)
	f:Hide()
	mini = f
	return f
end

--- the column of quick searches by the minimap button: shown, or hidden again
function UI.ToggleMiniMenu()
	local f = MakeMini()
	if f:IsShown() then f:Hide() return end
	local anchor = MiniAnchor()
	f:ClearAllPoints()
	local side = ns.db.minimapSide or "left"
	if side == "left" then f:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
	elseif side == "right" then f:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
	elseif side == "up" then f:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
	else f:SetPoint("TOP", anchor, "BOTTOM", 0, -2) end
	f:Show()
	RefreshMini()
end

--- the minimap button's click: its quick searches (Shift: the search box on the map)
function UI.MinimapClick(search)
	if search then UI.QuickSearch() return end
	UI.ToggleMiniMenu()
end

local function QuickRow()
	local out = {}
	for i = 1, #shown do out[i] = quick[i] end
	return out
end

local function MakeQuick(parent)
	local b = MakeSquare(parent)
	-- lit while its search is the one showing
	local glow = b:CreateTexture(nil, "OVERLAY")
	glow:SetAllPoints()
	glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	glow:SetBlendMode("ADD")
	glow:Hide()
	b.lit = glow
	-- the X shown on the pinned one, in its corner: click it to unpin
	local x = CreateFrame("Button", nil, b)
	x:SetSize(14, 14)
	x:SetPoint("TOPRIGHT", 5, 5)
	x:SetFrameLevel(b:GetFrameLevel() + 5)
	x:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
	x:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
	x:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
	x:SetScript("OnClick", function() if b.query then QuickPin(b.query) end end)
	x:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["Pinned: %s"]:format(b.label or ""), 1, 0.82, 0.1)
		GameTooltip:AddLine(L["Click to unpin it and take it off the map"], 1, 1, 1)
		GameTooltip:Show()
	end)
	x:SetScript("OnLeave", function() GameTooltip:Hide() end)
	x:Hide()
	b.unpin = x
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(self, button)
		if UI.JustDropped(self) then return end
		if button == "RightButton" then GameTooltip:Hide() QuickMenu(self) return end
		QuickPress(self.query)
		if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(self.label, 1, 0.82, 0.1)
		if self.fav then GameTooltip:AddLine(L["Your favourite search"], 0.6, 0.8, 1) end
		local pinned = self.query == ns.db.pinned
		if pinned then GameTooltip:AddLine(L["Pinned: it stays on the map and minimap"], 0.6, 1, 0.6) end
		GameTooltip:AddLine(lit == self.query and L["Click to clear"] or L["Show them all on the map"], 1, 1, 1)
		GameTooltip:AddLine(L["Right-click to pin it, change its icon, or take it off the bar"], 0.7, 0.7, 0.7, true)
		GameTooltip:AddLine(L["Drag to move it"], 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	UI.Draggable(b, QuickRow, function(self, to) UI.MoveButton(self.key, to) end)
	return b
end

--- the search button, the quick buttons you picked (in your order), the nearest and More
function UI.Layout()
	if not bar then return end
	wipe(shown)
	local hunter = IsHunter()
	for _, key in ipairs(ns.db.buttons) do
		local spec = UI.Spec(key)
		if spec and (hunter or not spec.hunter) and #shown < UI.MAX_BUTTONS then
			shown[#shown + 1] = spec
		end
	end
	-- (each in its own place off the bar's left, not off the button before it: a button being
	-- dragged then takes only itself along)
	local function At(slot) return 4 + slot * (BUTTON + 2) end
	searchBtn:ClearAllPoints()
	searchBtn:SetPoint("LEFT", bar, "LEFT", At(0), 0)
	for i, spec in ipairs(shown) do
		local b = quick[i] or MakeQuick(bar)
		quick[i] = b
		b.key, b.query, b.label, b.fav = spec.key, spec.query, spec.label, spec.fav
		ns.SetLook(b.icon, ns.LOOKS[spec.icon])
		b:ClearAllPoints()
		b:SetPoint("LEFT", bar, "LEFT", At(i) + 2, 0)
		b:Show()
	end
	for i = #shown + 1, #quick do
		quick[i]:Hide()
		quick[i].key, quick[i].query = nil, nil
	end
	near:ClearAllPoints()
	near:SetPoint("LEFT", bar, "LEFT", At(#shown + 1) + 4, 0)
	more:ClearAllPoints()
	more:SetPoint("LEFT", near, "RIGHT", 2, 0)
	if menu then menu:Hide() end
	UI.Place()
	LightQuick(Plain(edit:GetText()))
	LightSearch()
end

function UI.Create()
	if bar or not WorldMapFrame then return end
	local parent = WorldMapFrame.NavBar or WorldMapFrame

	bar = CreateFrame("Frame", "MapSeekFrame", parent)
	bar:SetHeight(BUTTON)
	bar:SetFrameLevel(parent:GetFrameLevel() + 10)

	-- the search button: opens the search box across the top bar
	searchBtn = MakeSquare(bar)
	searchBtn.icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
	searchBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local sl = searchBtn:CreateTexture(nil, "OVERLAY")
	sl:SetAllPoints()
	sl:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	sl:SetBlendMode("ADD")
	sl:Hide()
	searchBtn.lit = sl
	local sx = searchBtn:CreateTexture(nil, "OVERLAY", nil, 1)
	sx:SetPoint("TOPLEFT", 5, -5)
	sx:SetPoint("BOTTOMRIGHT", -5, 5)
	sx:SetTexture(STOP_ICON)
	sx:SetVertexColor(1, 0.35, 0.3)
	sx:Hide()
	searchBtn.clear = sx
	-- a little tab under the search button while a search is on the map (the button then an X):
	-- "Cancel search", with a point on it towards the button: a reminder that there's a search
	-- still on, and where it's taken off. Only a sign: clicks go through it. Not while the count
	-- or the drop-down is where it would go
	do
		local tip = CreateFrame("Frame", nil, searchBtn)
		tip:SetFrameLevel(searchBtn:GetFrameLevel() + 8)
		tip:EnableMouse(false)
		local GOLD = { 1, 0.82, 0.1 }
		-- (the point: a square stood on its corner, half of it behind the box, gold with the box's
		-- dark inside it)
		local point = tip:CreateTexture(nil, "BACKGROUND", nil, -3)
		point:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
		point:SetSize(10, 10)
		point:SetRotation(math.pi / 4)
		local pointIn = tip:CreateTexture(nil, "BACKGROUND", nil, -2)
		pointIn:SetColorTexture(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], 1)
		pointIn:SetSize(7.5, 7.5)
		pointIn:SetRotation(math.pi / 4)
		pointIn:SetPoint("CENTER", point, "CENTER")
		local tbg = tip:CreateTexture(nil, "BACKGROUND", nil, -1)
		tbg:SetAllPoints()
		tbg:SetColorTexture(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], 1)
		local tedge = {}
		for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			local t = tip:CreateTexture(nil, "BORDER")
			t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
			if i <= 2 then
				t:SetPoint(side .. "LEFT") t:SetPoint(side .. "RIGHT") t:SetHeight(1)
			else
				t:SetPoint("TOP" .. side) t:SetPoint("BOTTOM" .. side) t:SetWidth(1)
			end
			tedge[i] = t
		end
		-- (the box's edge left open where the point comes out of it)
		local gap = tip:CreateTexture(nil, "BORDER", nil, 1)
		gap:SetColorTexture(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], 1)
		gap:SetSize(11, 1)
		-- (moved a part of a pixel at a time: not held to the screen's pixels)
		for _, t in ipairs({ point, pointIn, tbg, gap, tedge[1], tedge[2], tedge[3], tedge[4] }) do
			if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
			if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
		end
		local ttext = ns.Text(tip, "GameFontHighlightSmall")
		ttext:SetPoint("CENTER", 0, 0)
		ttext:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		ttext:SetText(L["Cancel search"])
		tip:SetSize(ttext:GetStringWidth() + 16, 19)
		ns.OnSkin(function(S)
			if S.Font then S.Font(ttext) ttext:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
			tip:SetWidth(ttext:GetStringWidth() + 16)
		end)
		tip:Hide()
		local OFF = 9   -- pixels off the button
		local up, placed
		local function Place()
			up = ns.db.barPos == "bottom"
			if placed == up then return end
			placed = up
			point:ClearAllPoints()
			gap:ClearAllPoints()
			if up then
				point:SetPoint("CENTER", tip, "BOTTOM", 0, 0)
				gap:SetPoint("CENTER", tip, "BOTTOM", 0, 0.5)
			else
				point:SetPoint("CENTER", tip, "TOP", 0, 0)
				gap:SetPoint("CENTER", tip, "TOP", 0, -0.5)
			end
			-- (the bar moved to the map's other edge while it's up: put on that side now)
			if tip:IsShown() then
				tip:ClearAllPoints()
				if up then tip:SetPoint("BOTTOM", searchBtn, "TOP", 0, OFF)
				else tip:SetPoint("TOP", searchBtn, "BOTTOM", 0, -OFF) end
			end
		end
		-- (it fades and comes back, the whole of it together, on one unbroken wave worked out each
		-- frame: no start or end to it, so no catch where a looping animation turns round. Not
		-- moved: its words are held to whole pixels, and a drift of a few shows each one's step)
		local SECS, LOW = 1.8, 0.45
		local t = 0
		tip:SetScript("OnShow", function(self)
			self:ClearAllPoints()
			if up then self:SetPoint("BOTTOM", searchBtn, "TOP", 0, OFF)
			else self:SetPoint("TOP", searchBtn, "BOTTOM", 0, -OFF) end
			t = 0
			self:SetAlpha(1)
		end)
		tip:SetScript("OnUpdate", function(self, elapsed)
			-- (a frame that took long, the game in the background: not a jump in the wave)
			t = (t + math.min(elapsed, 0.1)) % SECS
			local wave = (1 - math.cos(t / SECS * 2 * math.pi)) / 2   -- 0 .. 1 .. 0
			self:SetAlpha(1 - (1 - LOW) * wave)
		end)
		local since = 0
		local watch = CreateFrame("Frame", nil, searchBtn)
		watch:SetScript("OnUpdate", function(_, elapsed)
			since = since + elapsed
			if since < 0.2 then return end
			since = 0
			local on = current ~= nil and ns.db.cancelTip ~= false
				and not (statusBox and statusBox:IsShown()) and not (list and list:IsShown())
			if on then Place() end
			if tip:IsShown() ~= on then tip:SetShown(on) end
		end)
		searchBtn.cancelTip = tip
	end
	searchBtn:SetScript("OnClick", function(self)
		-- (a search on the map: the X clears it, and the button's the scope again)
		if current then
			UI.Clear()
			if GameTooltip:IsOwned(self) and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
			return
		end
		if strip:IsShown() then
			CloseSearch()
		else
			OpenSearch()
		end
	end)
	searchBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["Search"], 1, 0.82, 0.1)
		GameTooltip:AddLine(L["NPCs, items vendors sell, skill books, mailboxes and more"], 1, 1, 1, true)
		if current then
			GameTooltip:AddLine(L["On the map: \"%s\""]:format(current), 0.5, 1, 0.5)
			GameTooltip:AddLine(L["Click to clear it"], 0.7, 0.7, 0.7)
		end
		if ns.db.pinned then GameTooltip:AddLine(L["Pinned: \"%s\""]:format(ns.db.pinned), 0.6, 0.8, 1) end
		GameTooltip:Show()
	end)
	searchBtn:HookScript("OnLeave", function() C_Timer.After(0, SyncSearch) end)

	strip = MakeStrip(WorldMapFrame.NavBar)
	edit = MakeEdit(strip)
	edit:SetPoint("LEFT", strip, "LEFT", 10, 0)   -- (the search template's border reaches out a little)
	edit:SetPoint("RIGHT", strip.favs, "LEFT", -6, 0)
	-- (EllesmereUI's look, but the box keeps the game's font and text inset: re-fonting the box
	-- itself leaves the cursor measured by the old font, drifting away from the letters)
	ns.OnSkin(function(S)
		S.EditBox(edit)
		if edit.Instructions then pcall(S.Font, edit.Instructions) end
	end)
	list = MakeList()
	-- (the status line hangs under the box, or its suggestions, when they're up: placed again as they come and go)
	for _, f in ipairs({ strip, list }) do
		f:HookScript("OnShow", function() Hang() end)
		f:HookScript("OnHide", function() Hang() end)
	end

	-- (an item shift-clicked, in a bag, in chat, while the search box has the cursor: its link in
	-- the box, "[Copper Ore]", as in chat's; searched for by its name)
	-- (the game's own call for it, by whichever name this game has: the newer ChatFrameUtil's, the
	-- older ChatEdit_InsertLink. Once for a click, though one may call the other)
	do
		local last = 0
		local function Take(link)
			if not (edit and edit:IsVisible() and edit:HasFocus() and type(link) == "string") then return end
			if not link:find("|Hitem:", 1, true) then return end
			local now = GetTime()
			if now - last < 0.1 then return end
			last = now
			edit:Insert(link)
			-- (no chat box took the link, so the game goes on to its next meaning of a shift-click
			-- on a stack: splitting it, in a little window that takes the keys. Not wanted here:
			-- closed, and the box takes the keys back, the cursor after what's in it)
			local function Back()
				if StackSplitFrame and StackSplitFrame:IsShown() then StackSplitFrame:Hide() end
				if not (edit and edit:IsVisible()) then return end
				edit:SetFocus()
				edit:SetCursorPosition(#(edit:GetText() or ""))
			end
			Back()
			C_Timer.After(0, Back)
			C_Timer.After(0.15, Back)
		end
		if hooksecurefunc then
			if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
				hooksecurefunc(ChatFrameUtil, "InsertLink", Take)
			end
			if type(ChatEdit_InsertLink) == "function" then hooksecurefunc("ChatEdit_InsertLink", Take) end
		end
	end
	-- (the box hovered, an item's link in it: the item's tooltip)
	edit:HookScript("OnEnter", function(self)
		local link = (self:GetText() or ""):match("|H(item:[^|]+)|h")
		if not link then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() else GameTooltip:Hide() end
	end)
	edit:HookScript("OnLeave", function(self)
		if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end)
	edit:SetScript("OnEnterPressed", function(self)
		if list:IsShown() and sel and listData[sel] then
			Pick(listData[sel])
			return
		end
		UI.Run(self:GetText(), "enter")
		self:ClearFocus()
	end)
	edit:SetScript("OnTabPressed", function()
		local d = list:IsShown() and listData[sel or 1]
		if d then Pick(d) end
	end)
	edit:SetScript("OnEscapePressed", function(self)
		-- (out of the box, the list closed: the strip stays open, as after Enter)
		if list:IsShown() then HideList() end
		self:ClearFocus()
	end)
	edit:HookScript("OnArrowPressed", function(_, key)
		local n = #listData
		if not list:IsShown() or n == 0 then return end
		if key == "DOWN" then sel = sel and (sel % n) + 1 or 1
		elseif key == "UP" then sel = sel and ((sel - 2) % n) + 1 or n
		else return end
		Highlight()
		UI.PreviewFarm(listData[sel])
	end)
	edit:HookScript("OnTextChanged", function(self, userInput)
		if not userInput then return end
		StopBlink()   -- (changed: back to its own colour now)
		if liveTimer then liveTimer:Cancel() liveTimer = nil end
		local text = strtrim(Plain(self:GetText()) or "")
		if text == "" then
			lastTyped, current = nil, nil
			SetNear(nil)
			ns.Pins.Clear()
			if ns.Route.Preview then ns.Route.Preview(nil) end
			LightQuick(nil)
			LightSearch()
			SetStatus(nil)
			ShowRecent()
			return
		end
		local count = ShowSuggest(text, false)
		if #text >= LIVE_MIN then
			liveTimer = C_Timer.NewTimer(LIVE_DELAY, function()
				liveTimer = nil
				UI.Run(text)
				-- (little to suggest: maybe it's misspelled. Slower, so only once typing stops)
				if count < FIX_BELOW and #text >= 4 and self:HasFocus() and strtrim(Plain(self:GetText()) or "") == text then
					ShowSuggest(text, true)
				end
			end)
		end
	end)
	-- recents: clicking into the empty box shows them
	edit:HookScript("OnEditFocusGained", function(self)
		if strtrim(self:GetText() or "") == "" then ShowRecent() end
	end)
	edit:HookScript("OnEditFocusLost", function()
		KeepTyped()
		-- (a click on a row takes the focus first: leave the list up for that click)
		if not (list:IsMouseOver() or strip:IsMouseOver()) then HideList() end
		C_Timer.After(0, SyncSearch)
	end)

	-- More: the quick buttons past the first 5, and the settings
	more = MakeSquare(bar)
	more.icon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
	local ml = more:CreateTexture(nil, "OVERLAY")
	ml:SetAllPoints()
	ml:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	ml:SetBlendMode("ADD")
	ml:Hide()
	more.lit = ml
	more:SetScript("OnClick", function()
		GameTooltip:Hide()
		ToggleMenu()
	end)
	more:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["More"], 1, 0.82, 0.1)
		local n = #UI.ExtraSpecs()
		GameTooltip:AddLine(n > 0 and (n == 1 and L["%d more quick button, and the settings"] or L["%d more quick buttons, and the settings"]):format(n)
			or L["The settings"], 1, 1, 1)
		GameTooltip:Show()
	end)

	-- the nearest match: hover to point it out on the map, click to be taken there (a waypoint)
	near = MakeSquare(bar)
	near.icon:SetTexture("Interface\\Icons\\Ability_Tracking")
	near.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	near:SetScript("OnClick", function(self)
		local d = ns.Pins.Nearest()   -- (again: you may have moved since the search)
		SetNear(d)
		if d then
			UI.TakeMeThere(d)
		else
			SetStatus(current and L["None of these are on your continent."] or L["Search first, then this finds the closest."],
				1, 0.6, 0.3)
		end
		if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
	end)
	near:SetScript("OnEnter", function(self)
		local d = ns.Pins.Nearest()
		SetNear(d)
		ns.Pins.Spotlight(d, true)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["Take me to the nearest"], 1, 0.82, 0.1)
		if d then
			GameTooltip:AddLine(("%s, %s%s"):format(d.name, ns.ZoneName(d.ui), Yards(ns.Pins.Distance(d))), 1, 1, 1)
			GameTooltip:AddLine(L["Pulsing on the map now, ringed in green"], 0.7, 0.7, 0.7, true)
			GameTooltip:AddLine(L["Click to set a waypoint to it"], 0.5, 1, 0.5)
		else
			GameTooltip:AddLine(current and L["None of these matches are on your continent."]
				or L["Search first, then this finds the closest match."], 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	near:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		ns.Pins.Spotlight(self.target, false)
	end)
	SetNear(nil)

	UI.Layout()

	-- the count, in a dark pill just under the bar (or the box) on the map; while Questie's data
	-- is read, a gold fill across it shows how far that is
	statusBox = CreateFrame("Frame", nil, bar)
	statusBox:SetFrameLevel(bar:GetFrameLevel() + 5)
	local sbg = statusBox:CreateTexture(nil, "BACKGROUND")
	sbg:SetAllPoints()
	sbg:SetColorTexture(unpack(PANEL_BG))
	local sedge = statusBox:CreateTexture(nil, "BORDER")
	sedge:SetPoint("BOTTOMLEFT")
	sedge:SetPoint("BOTTOMRIGHT")
	sedge:SetHeight(1)
	sedge:SetColorTexture(unpack(PANEL_EDGE))
	local fill = statusBox:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMLEFT", 1, 2)
	fill:SetColorTexture(1, 0.82, 0.1, 0.22)
	fill:Hide()
	statusBox.fill = fill
	ns.OnSkin(function(S)
		sbg:Hide()
		sedge:Hide()
		S.Panel(statusBox)
	end)
	status = ns.Text(statusBox, "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", 7, -4)
	status:SetJustifyH("LEFT")
	ns.SkinText(status)
	status:SetShadowOffset(1, -1)
	status:SetShadowColor(0, 0, 0, 1)
	statusBox:Hide()
	local fade = statusBox:CreateAnimationGroup()
	local a = fade:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0)
	a:SetDuration(0.6)
	fade:SetScript("OnFinished", function() statusBox:Hide() statusBox:SetAlpha(1) end)
	statusBox.fade = fade

	-- closing the map closes the search: everything, or (/seek close list) only the search. A
	-- pinned search stays (or comes back, if another was on the map)
	bar:SetScript("OnHide", function()
		quickOpened = nil
		-- (the suggestions' vocabulary let go a minute after the map closes: built again on the
		-- next search typed)
		if releaseTimer then releaseTimer:Cancel() end
		releaseTimer = C_Timer.NewTimer(RELEASE_AFTER, function()
			releaseTimer = nil
			if not WorldMapFrame:IsShown() then
				ns.Suggest.Release()
				if ns.Search.Release then ns.Search.Release() end
				if ns.Farm and ns.Farm.Release then ns.Farm.Release() end
				if ns.Route and ns.Route.Release then ns.Route.Release() end
			end
		end)
		if menu then menu:Hide() end
		strip:Hide()
		if lingerTimer then lingerTimer:Cancel() lingerTimer = nil end
		local going = ns.Route.Active and ns.Route.Active()
		if ns.Pins.HasFarm() and going and (going.loop or going.after) then
			-- (a farming loop you're riding: its veins and herbs stay, on the map and the minimap,
			-- until the farming's stopped)
			ResetSearch()
		elseif ns.db.pinned then
			local q = ns.db.pinned
			ResetSearch()
			if current ~= q then ShowPinned() end
		elseif ns.Pins.HasDrops() then
			-- (where an item's found: kept while the map's open, gone with it)
			UI.Clear()
		elseif ns.db.closeClears == "list" then
			ResetSearch()
		elseif current and lit == current and (ns.db.linger or 0) > 0 then
			-- a quick button's search: on the map and minimap a little longer, then cleared
			local q = current
			ResetSearch()
			lingerTimer = C_Timer.NewTimer(ns.db.linger, function()
				lingerTimer = nil
				if current == q and ns.db.pinned ~= q and not WorldMapFrame:IsShown() then UI.Clear() end
			end)
		else
			UI.Clear()
		end
	end)
	-- (the map open again: a lingering search stays until the map next closes)
	bar:SetScript("OnShow", function()
		if lingerTimer then lingerTimer:Cancel() lingerTimer = nil end
		if releaseTimer then releaseTimer:Cancel() releaseTimer = nil end
		-- (the search open from the start, when set: the search button hides it for the breadcrumbs.
		-- Not typed into until clicked, so the map's keys still work)
		if ns.db.searchOpen and not strip:IsShown() then strip:Show() end
		ns.Pins.AprilFools()
		-- (its button lit again, so a click clears it)
		if current then LightQuick(current) LightSearch() end
	end)
	-- (the pinned search's minimap markers are the zone you're in: a new zone, its own)
	local zones = CreateFrame("Frame")
	zones:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	zones:SetScript("OnEvent", function()
		if ns.db.pinned and current == ns.db.pinned and not WorldMapFrame:IsShown() then
			C_Timer.After(1, ShowPinned)
		end
	end)

	-- (the nav bar and the tracking button are laid out when the map shows, and again on resize)
	WorldMapFrame:HookScript("OnShow", function()
		C_Timer.After(0, function()
			UI.Place()
			ns.Pins.Raise()   -- (markers kept from before: over the icons of the map as built now)
		end)
	end)
	WorldMapFrame:HookScript("OnSizeChanged", function() C_Timer.After(0, UI.Place) end)
	-- zone-only: the search follows the map to the zone it shows now
	local againTimer
	if WorldMapFrame.OnMapChanged then
		hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
			if not (ns.db.zoneOnly and current) then return end
			if againTimer then againTimer:Cancel() end
			againTimer = C_Timer.NewTimer(0.1, function() againTimer = nil UI.Again() end)
		end)
	end
	UI.Place()
end

function UI.Bar() return bar end

--------------------------------------------------------------------------------
-- Move mode: drag the bar (and the search box with it) anywhere on the map. Its place is kept
-- as a share of the map's size; right-click (or the settings' Done) to finish
--------------------------------------------------------------------------------

local function SaveSpot()
	local area = MapArea()
	local r, t = bar:GetRight(), bar:GetTop()
	local l, top = area:GetLeft(), area:GetTop()
	local w, h = area:GetWidth(), area:GetHeight()
	if not (r and t and l and top and w > 0 and h > 0) then return end
	local bs, as = bar:GetEffectiveScale(), area:GetEffectiveScale()
	local x = (r * bs - l * as) / (w * as)
	local y = (top * as - t * bs) / (h * as)
	-- (kept on the map)
	ns.db.barAt = { math.max(0.05, math.min(1, x)), math.max(0, math.min(0.95, y)) }
end

--- move mode on or off (nil: the other). On: the bar's place is "custom" from now on
function UI.MoveMode(on)
	if not bar then return end
	if on == nil then on = not (mover and mover:IsShown()) end
	if not on then
		if mover then mover:Hide() end
		if ns.Settings.Refresh then ns.Settings.Refresh() end
		return
	end
	if not WorldMapFrame:IsShown() then
		if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
	end
	if ns.db.barPos ~= "custom" then
		-- (from where it is now)
		SaveSpot()
		ns.db.barPos = "custom"
		UI.Place()
	end
	if strip and not strip:IsShown() then strip:Show() end
	if not mover then
		mover = CreateFrame("Button", nil, WorldMapFrame)
		mover:SetFrameStrata("DIALOG")
		mover:RegisterForDrag("LeftButton")
		mover:RegisterForClicks("RightButtonUp")
		local edge = mover:CreateTexture(nil, "BACKGROUND")
		edge:SetPoint("TOPLEFT", -1, 1)
		edge:SetPoint("BOTTOMRIGHT", 1, -1)
		edge:SetColorTexture(0.3, 1, 0.4, 0.7)
		local bg = mover:CreateTexture(nil, "BORDER")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.25, 0.08, 0.85)
		local t = ns.Text(mover, "GameFontHighlightSmall")
		t:SetPoint("LEFT", 6, 0)
		t:SetPoint("RIGHT", -6, 0)
		t:SetText(L["Drag to move the search bar. Right-click when done."])
		ns.SkinText(t)
		mover:SetScript("OnDragStart", function()
			bar:SetMovable(true)
			bar:StartMoving()
		end)
		mover:SetScript("OnDragStop", function()
			bar:StopMovingOrSizing()
			if bar.SetUserPlaced then pcall(bar.SetUserPlaced, bar, false) end
			SaveSpot()
			UI.Place()
		end)
		mover:SetScript("OnClick", function() UI.MoveMode(false) end)
		bar:HookScript("OnHide", function() UI.MoveMode(false) end)
	end
	mover:ClearAllPoints()
	mover:SetPoint("TOPLEFT", strip or bar, "TOPLEFT", -4, 4)
	mover:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 4, -4)
	mover:Show()
	if ns.Settings.Refresh then ns.Settings.Refresh() end
end

function UI.Moving() return mover ~= nil and mover:IsShown() end

--- the bar's place: "top", "bottom" or "custom" (custom with nowhere kept yet: move mode)
function UI.SetBarPos(pos)
	ns.db.barPos = pos
	if mover and mover:IsShown() and pos ~= "custom" then mover:Hide() end
	UI.Place()
	if pos == "custom" and not ns.db.barAt then UI.MoveMode(true) end
	if ns.Settings.Refresh then ns.Settings.Refresh() end
end
