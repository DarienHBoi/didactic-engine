-- Shared Forever launcher. Embed this exact file before each addon's core.
-- Every addon supplies its own SavedVariables-backed storage table.

local API_VERSION = 9
local launcher = _G.ForeverAddonLauncher
if type(launcher) ~= "table" then
	launcher = { addons = {} }
	_G.ForeverAddonLauncher = launcher
elseif (tonumber(launcher.apiVersion) or 0) > API_VERSION then
	return
elseif (tonumber(launcher.apiVersion) or 0) == API_VERSION and launcher.initialized then
	return
end
launcher.addons = launcher.addons or {}
launcher.apiVersion = API_VERSION
launcher.supportsCombatClickForwarding = true

local ORDER = {
	ForeverCompass = 10, ForeverRares = 20, ForeverGather = 30,
	ForeverRollCheck = 40, ForeverMarket = 50, ForeverSalvage = 60,
	ForeverFishing = 65, ForeverDualGather = 70,
}

local function Direction(x, y)
	x, y = tonumber(x), tonumber(y)
	if not x or not y then return nil end
	local length = math.sqrt(x * x + y * y)
	if length < 0.01 then return nil end
	return x / length, y / length
end

local function Ctrl()
	return IsControlKeyDown and IsControlKeyDown()
end

-- Secure click forwarding is opt-in per entry. The addon owns its target's
-- preparation, action and cleanup; the launcher only preserves the click chain.
local function Combat() return InCombatLockdown and InCombatLockdown() end
local function DeferLayout()
    launcher.layoutPending=true
    if not launcher.layoutEvents then
        local events=CreateFrame("Frame")
        events:SetScript("OnEvent",function()
            events:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if launcher.layoutPending then launcher.layoutPending=nil; launcher:RefreshButtons() end
        end)
        launcher.layoutEvents=events
    end
    launcher.layoutEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
end
local function ConfigureSecureClick(button, entry, panel)
    button:SetAttribute("launcher-ignore-click",button.foreverIgnoreClick)
    button:SetAttribute("useOnKeyDown",false)
    button:SetAttribute("pressAndHoldAction",false)
    local session=entry and entry.combatClickSession
    local target=entry and entry.combatClickTarget
    local enabled=session~=nil and target~=nil
    -- SetFrameRef requires a real frame; nil cannot clear an optional reference.
    -- Explicit flags disable retained refs when a pooled row changes entry.
    button:SetAttribute("launcher-combat-close-enabled",enabled)
    if enabled then button:SetFrameRef("combat-session",session) end
    button:SetAttribute("clickbutton1",target)
    button:SetAttribute("launcher-has-panel",panel~=nil)
    if panel then button:SetFrameRef("launcher-panel",panel) end
    if button.foreverSecureClick==API_VERSION or button.foreverSecureFamily then return end
    if button.foreverSecureClick then SecureHandlerUnwrapScript(button,"OnClick") end
    button.foreverSecureClick=API_VERSION
    SecureHandlerWrapScript(button,"OnClick",button,[[
        self:SetAttribute("type1",nil)
        self:SetAttribute("launcher-combat-click",nil)
        if self:GetAttribute("launcher-ignore-click") or down or IsControlKeyDown() then return false end
        if SecureCmdOptionParse("[combat]combat") then
            if self:GetAttribute("launcher-has-panel") then
                self:GetFrameRef("launcher-panel"):Hide()
            end
            local session=self:GetAttribute("launcher-combat-close-enabled") and self:GetFrameRef("combat-session")
            if button == "LeftButton" and session and session:IsShown() then
                self:SetAttribute("type1","click")
                self:SetAttribute("launcher-combat-click",true)
            end
        end
    ]])
end
local function IgnoreClick(button, value)
    button.foreverIgnoreClick=value
    if button.foreverSecureClick or button.foreverSecureFamily then
        if Combat() then DeferLayout() else button:SetAttribute("launcher-ignore-click",value) end
    end
end

-- Display strings are optional per registration, never shared saved state.
-- The embed has no dependency on Fishing or its locale/catalogue owner.
local function DisplayText(entry, key, fallback, ...)
    local pack = entry and entry.displayText
    local text = type(pack) == "table" and pack[key]
    if type(text) ~= "string" or text == "" then text = fallback end
    if select("#", ...) == 0 then return text end
    local ok, result = pcall(string.format, text, ...)
    if ok then return result end
    return string.format(fallback, ...)
end

function launcher:GetFamilyDisplayText(key, fallback, ...)
    -- Stable IDs choose the opt-in provider, independently of load/list order.
    -- One provider owns the whole family language; missing keys use English.
    local provider, providerID
    for id, entry in pairs(self.addons) do
        if type(entry.displayText) == "table" and (not providerID or id < providerID) then
            provider, providerID = entry, id
        end
    end
    return DisplayText(provider, key, fallback, ...)
end

local function CopyIDs(ids)
	local copy, seen = {}, {}
	if type(ids) ~= "table" then return copy end
	for _, id in ipairs(ids) do
		if type(id) == "string" and not seen[id] then
			copy[#copy + 1] = id
			seen[id] = true
		end
	end
	return copy
end

local function AddBackdrop(frame)
	if not frame.SetBackdrop then return end
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.015, 0.014, 0.012, 0.98)
	frame:SetBackdropBorderColor(0.82, 0.58, 0.20, 1)
end

function launcher:GetSortedAddons()
	local entries = {}
	for _, entry in pairs(self.addons) do entries[#entries + 1] = entry end
	local positions = {}
	for index, id in ipairs(self.listOrder or {}) do positions[id] = index end
	table.sort(entries, function(a, b)
		local aOrder, bOrder = positions[a.id], positions[b.id]
		if aOrder and bOrder then return aOrder < bOrder end
		if aOrder then return true end
		if bOrder then return false end
		local aName = string.lower(tostring(a.title or a.id))
		local bName = string.lower(tostring(b.title or b.id))
		if aName ~= bName then return aName < bName end
		return a.id < b.id
	end)
	return entries
end

function launcher:GetFamilyAddons()
	local all = self:GetSortedAddons()
	if #all <= 1 then return {} end
	local family = {}
	for _, entry in ipairs(all) do
		-- Hidden icons retain their entry in the family list, including an entry
		-- previously detached. Icon contributors are filtered in RefreshButtons.
		if not (entry.storage and entry.storage.detached) or (entry.storage and entry.storage.iconHidden) then
			family[#family + 1] = entry
		end
	end
	return family
end

function launcher:PlaceOnEdge(button, x, y)
	if Combat() then DeferLayout(); return end
	if not button or not Minimap then return end
	x, y = Direction(x, y)
	if not x then x, y = -0.707107, 0.707107 end
	if GetMinimapShape and GetMinimapShape() == "SQUARE" then
		local edge = math.max(math.abs(x), math.abs(y))
		if edge > 0 then x, y = x / edge, y / edge end
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER",
		x * ((Minimap:GetWidth() or 140) / 2 + 7),
		y * ((Minimap:GetHeight() or 140) / 2 + 7))
end

function launcher:DefaultIndividualDirection(entry)
	local slot = math.floor((ORDER[entry.id] or entry.order or 80) / 10)
	local angle = math.rad(60 - (((slot - 1) % 10) * 35))
	return math.cos(angle), math.sin(angle)
end

function launcher:PositionIndividual(entry)
	if not entry.generatedButton then return end
	local x, y = Direction(entry.storage.iconX, entry.storage.iconY)
	if not x then x, y = self:DefaultIndividualDirection(entry) end
	self:PlaceOnEdge(entry.generatedButton, x, y)
end

function launcher:RepositionButtons()
	self:PlaceOnEdge(self.button, self.familyX, self.familyY)
	for _, entry in pairs(self.addons) do self:PositionIndividual(entry) end
end

function launcher:EnsureResizeHook()
	if self.resizeHooked or not Minimap or not Minimap.HookScript then return end
	self.resizeHooked = true
	Minimap:HookScript("OnSizeChanged", function() launcher:RepositionButtons() end)
end

function launcher:AdoptFamilyPosition(storage)
	if type(storage) ~= "table" then return end
	local x, y = Direction(storage.familyX, storage.familyY)
	local changed = tonumber(storage.familyChangedAt) or 0
	if x and (not self.familyX or changed > (self.familyChangedAt or 0)) then
		self.familyX, self.familyY, self.familyChangedAt = x, y, changed
		self:PlaceOnEdge(self.button, x, y)
	end
	if self.familyX then
		for _, entry in pairs(self.addons) do
			if type(entry.storage) == "table" then
				entry.storage.familyX = self.familyX
				entry.storage.familyY = self.familyY
				entry.storage.familyChangedAt = self.familyChangedAt
			end
		end
	end
end

function launcher:SaveFamilyPosition(x, y)
	self.familyX, self.familyY = x, y
	self.familyChangedAt = time and time() or ((self.familyChangedAt or 0) + 1)
	for _, entry in pairs(self.addons) do
		if type(entry.storage) == "table" then
			entry.storage.familyX, entry.storage.familyY = x, y
			entry.storage.familyChangedAt = self.familyChangedAt
		end
	end
end

function launcher:AdoptPanelPosition(storage)
	if type(storage) ~= "table" then return end
	local x, y = tonumber(storage.panelX), tonumber(storage.panelY)
	local changed = tonumber(storage.panelChangedAt) or 0
	if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1
		and (not self.panelX or changed > (self.panelChangedAt or 0)) then
		self.panelX, self.panelY, self.panelChangedAt = x, y, changed
	end
	if self.panelX then
		for _, entry in pairs(self.addons) do
			if type(entry.storage) == "table" then
				entry.storage.panelX = self.panelX
				entry.storage.panelY = self.panelY
				entry.storage.panelChangedAt = self.panelChangedAt
			end
		end
	end
end

function launcher:PlacePanel(panel)
	if Combat() then DeferLayout(); return end
	if not panel then return end
	panel:ClearAllPoints()
	if self.panelX and self.panelY and UIParent then
		local width, height = UIParent:GetWidth(), UIParent:GetHeight()
		if width and height and width > 0 and height > 0 then
			local x = math.min(self.panelX * width, math.max(0, width - panel:GetWidth()))
			local y = math.min(self.panelY * height, math.max(0, height - panel:GetHeight()))
			panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, -y)
			return
		end
	end
	panel:SetPoint("TOPRIGHT", Minimap or UIParent, "TOPLEFT", -12, 0)
end

function launcher:SavePanelPosition(panel)
	if not panel or not UIParent then return end
	local left, top = panel:GetLeft(), panel:GetTop()
	local uiLeft, uiTop = UIParent:GetLeft(), UIParent:GetTop()
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	if not left or not top or not uiLeft or not uiTop or not width or not height
		or width <= 0 or height <= 0 then return end
	self.panelX = math.max(0, math.min(1, (left - uiLeft) / width))
	self.panelY = math.max(0, math.min(1, (uiTop - top) / height))
	self.panelChangedAt = time and time() or ((self.panelChangedAt or 0) + 1)
	for _, entry in pairs(self.addons) do
		if type(entry.storage) == "table" then
			entry.storage.panelX = self.panelX
			entry.storage.panelY = self.panelY
			entry.storage.panelChangedAt = self.panelChangedAt
		end
	end
	self:PlacePanel(panel)
end

function launcher:AdoptListOrder(storage)
	if type(storage) ~= "table" then return end
	local ids = CopyIDs(storage.listOrder)
	local changed = tonumber(storage.listChangedAt) or 0
	if #ids > 0 and (not self.listOrder or changed > (self.listChangedAt or 0)) then
		self.listOrder, self.listChangedAt = ids, changed
	end
	if self.listOrder then
		for _, entry in pairs(self.addons) do
			if type(entry.storage) == "table" then
				entry.storage.listOrder = CopyIDs(self.listOrder)
				entry.storage.listChangedAt = self.listChangedAt
			end
		end
	end
end

function launcher:SaveListOrder(entries)
	local ids, seen = {}, {}
	for _, entry in ipairs(entries) do
		ids[#ids + 1] = entry.id
		seen[entry.id] = true
	end
	-- Keep temporarily unloaded addons in the saved order for their next login.
	for _, id in ipairs(self.listOrder or {}) do
		if not seen[id] then ids[#ids + 1] = id end
	end
	self.listOrder = ids
	self.listChangedAt = time and time() or ((self.listChangedAt or 0) + 1)
	for _, entry in pairs(self.addons) do
		if type(entry.storage) == "table" then
			entry.storage.listOrder = CopyIDs(ids)
			entry.storage.listChangedAt = self.listChangedAt
		end
	end
end

function launcher:MoveAddon(id, targetID, after)
	if Combat() then return false end
	if id == targetID then return false end
	local entries = self:GetSortedAddons()
	local source
	for index, entry in ipairs(entries) do
		if entry.id == id then source = table.remove(entries, index); break end
	end
	if not source then return false end
	local targetIndex
	for index, entry in ipairs(entries) do
		if entry.id == targetID then targetIndex = index; break end
	end
	if not targetIndex then return false end
	table.insert(entries, targetIndex + (after and 1 or 0), source)
	self:SaveListOrder(entries)
	self:RefreshButtons()
	return true
end

function launcher:GetDropTarget()
	local panel = self.panel
	local entries = self:GetFamilyAddons()
	if not panel or #entries == 0 or not GetCursorPosition then return nil end
	local scale = panel:GetEffectiveScale() or 1
	if scale <= 0 then return nil end
	local cursorX, cursorY = GetCursorPosition()
	cursorX, cursorY = cursorX / scale, cursorY / scale
	local left, right = panel:GetLeft(), panel:GetRight()
	local top, bottom = panel:GetTop(), panel:GetBottom()
	if not left or not right or not top or not bottom
		or cursorX < left - 12 or cursorX > right + 12
		or cursorY < bottom - 12 or cursorY > top + 12 then return nil end
	for index, entry in ipairs(entries) do
		local row = panel.rows[index]
		local rowTop, rowBottom = row:GetTop(), row:GetBottom()
		if rowTop and rowBottom and cursorY >= (rowTop + rowBottom) / 2 then
			return entry.id, false, row
		end
	end
	return entries[#entries].id, true, panel.rows[#entries]
end

function launcher:UpdateDropLine()
	local panel = self.panel
	if not panel or not panel.dropLine then return end
	local targetID, after, row = self:GetDropTarget()
	if not targetID or not row then panel.dropLine:Hide(); return end
	panel.dropLine:ClearAllPoints()
	panel.dropLine:SetWidth(math.max(1, panel:GetWidth() - 20))
	panel.dropLine:SetPoint("TOPLEFT", row, after and "BOTTOMLEFT" or "TOPLEFT",
		0, after and -1 or 1)
	panel.dropLine:Show()
end

function launcher:DragFromCursor(entry)
	if not GetCursorPosition or not Minimap then return end
	local centerX, centerY = Minimap:GetCenter()
	if not centerX or not centerY then return end
	local scale = Minimap:GetEffectiveScale() or 1
	if scale <= 0 then return end
	local cursorX, cursorY = GetCursorPosition()
	local x, y = Direction(cursorX / scale - centerX, cursorY / scale - centerY)
	if not x then return end
	if entry then
		entry.storage.iconX, entry.storage.iconY = x, y
		self:PositionIndividual(entry)
	else
		self:SaveFamilyPosition(x, y)
		self:PlaceOnEdge(self.button, x, y)
	end
end

function launcher:InstallDrag(button, entry)
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(owner)
		if Combat() then return end
		IgnoreClick(owner,true)
		if not (owner.foreverEntry or entry) and launcher.panel then launcher.panel:Hide() end
		owner:SetScript("OnUpdate", function() launcher:DragFromCursor(owner.foreverEntry or entry) end)
		if GameTooltip then GameTooltip:Hide() end
	end)
	button:SetScript("OnDragStop", function(owner)
		if Combat() then owner:SetScript("OnUpdate",nil); IgnoreClick(owner,nil); return end
		launcher:DragFromCursor(owner.foreverEntry or entry)
		owner:SetScript("OnUpdate", nil)
		if C_Timer and C_Timer.After then
			C_Timer.After(0, function() IgnoreClick(owner,nil) end)
		else
			IgnoreClick(owner,nil)
		end
	end)
end

function launcher:RefreshPanel()
	if Combat() then DeferLayout(); return end
	local panel = self.panel
	if not panel then return end
	local entries = self:GetFamilyAddons()
	local widestText = 0
	for _, row in ipairs(panel.rows or {}) do
		row:Hide()
		if row.highlight then row.highlight:Hide() end
	end
	for index, entry in ipairs(entries) do
		local row = panel.rows[index]
		if not row then
			row = CreateFrame("Button", nil, panel,"SecureActionButtonTemplate,SecureHandlerBaseTemplate")
			row:SetHeight(46)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(34, 34)
			row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
			row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -3)
			row.subtitle = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			row.subtitle:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
			row.highlight = row:CreateTexture(nil, "BACKGROUND")
			row.highlight:SetAllPoints(row)
			row.highlight:SetColorTexture(1, 0.82, 0, 0.12)
			row.highlight:Hide()
			panel.rows[index] = row
		end
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:RegisterForDrag("LeftButton")
		row:SetScript("OnDragStart", function(button)
			if Combat() then return end
			IgnoreClick(button,true)
			launcher.draggingAddon = button.entry.id
			button:SetScript("OnUpdate", function() launcher:UpdateDropLine() end)
			launcher:UpdateDropLine()
			if GameTooltip then GameTooltip:Hide() end
		end)
		row:SetScript("OnDragStop", function(button)
			button:SetScript("OnUpdate", nil)
			local targetID, after = launcher:GetDropTarget()
			launcher.draggingAddon = nil
			if panel.dropLine then panel.dropLine:Hide() end
			if targetID then launcher:MoveAddon(button.entry.id, targetID, after) end
			if C_Timer and C_Timer.After then
				C_Timer.After(0, function() IgnoreClick(button,nil) end)
			else
				IgnoreClick(button,nil)
			end
		end)
		row:SetScript("OnEnter", function(button)
			button.highlight:Show()
			if launcher.draggingAddon then return end
			if not GameTooltip then return end
			GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
			GameTooltip:SetText(button.entry.title or button.entry.id, 1, 0.82, 0)
			GameTooltip:AddLine(button.entry.listHint or DisplayText(button.entry, "open", "Click: open addon"), 0.85, 0.85, 0.85)
			GameTooltip:AddLine(DisplayText(button.entry, "separate", "Ctrl-click: separate minimap icon"), 0.75, 0.75, 0.75)
			GameTooltip:AddLine(DisplayText(button.entry, "reorder", "Drag: reorder the addon list"), 0.75, 0.75, 0.75)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function(button)
			button.highlight:Hide()
			if GameTooltip then GameTooltip:Hide() end
		end)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -45 - ((index - 1) * 46))
		row:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
		row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		row.title:SetText(entry.title or entry.id)
		row.subtitle:SetText(entry.subtitle or "")
		widestText = math.max(widestText,
			row.title.GetStringWidth and row.title:GetStringWidth() or 0,
			row.subtitle.GetStringWidth and row.subtitle:GetStringWidth() or 0)
		row.entry = entry
		ConfigureSecureClick(row,entry,panel)
		row:SetScript("PostClick", function(button, mouseButton)
			if button.foreverIgnoreClick or button:GetAttribute("launcher-ignore-click") then return end
			if Ctrl() then
				launcher:SetDetached(button.entry.id, true)
				return
			end
			if not Combat() then panel:Hide() end
			if button:GetAttribute("launcher-combat-click") then return end
			local current = button.entry
			if type(current.listClick) == "function" then
				current.listClick(mouseButton)
			elseif current.individualButton and type(current.individualButton.foreverLauncherOriginalOnClick) == "function" then
				current.individualButton.foreverLauncherOriginalOnClick(current.individualButton, mouseButton)
			elseif type(current.open) == "function" then
				current.open()
			end
		end)
		row:Show()
	end
	panel:SetWidth(math.max(218, math.min(320, math.ceil(widestText + 68))))
	panel:SetHeight(74 + (#entries * 46))
	if panel.hint then panel.hint:SetText("Ctrl-click: separate icon") end
	if #entries == 0 then panel:Hide() end
end

function launcher:EnsurePanel()
    if Combat() then DeferLayout(); return self.panel end
    if self.panel and not self.panel.foreverSecurePanel then
        self.panel:Hide(); self.panel=nil -- Upgrade an earlier embedded copy out of combat.
    end
	if self.panel then
		if not self.panel.foreverDragReady then
			self.panel.foreverDragReady = true
			self.panel:SetMovable(true)
			self.panel:RegisterForDrag("LeftButton")
			self.panel:SetScript("OnDragStart", function(panel)
				if Combat() then return end
				panel:StartMoving()
			end)
			self.panel:SetScript("OnDragStop", function(panel)
				if Combat() then return end
				panel:StopMovingOrSizing()
				launcher:SavePanelPosition(panel)
			end)
		end
		if not self.panel.hint then
			local hint = self.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			hint:SetPoint("BOTTOMLEFT", self.panel, "BOTTOMLEFT", 14, 10)
			hint:SetTextColor(0.75, 0.72, 0.65)
			self.panel.hint = hint
		end
		if not self.panel.dropLine then
			local overlay = CreateFrame("Frame", nil, self.panel)
			overlay:SetAllPoints(self.panel)
			overlay:SetFrameLevel(self.panel:GetFrameLevel() + 10)
			overlay:EnableMouse(false)
			local line = overlay:CreateTexture(nil, "OVERLAY")
			line:SetColorTexture(1, 0.82, 0, 0.95)
			line:SetHeight(2)
			line:Hide()
			self.panel.dropLine = line
		end
		return self.panel
	end
	local template = "SecureHandlerBaseTemplate" .. (BackdropTemplateMixin and ",BackdropTemplate" or "")
	local panel = CreateFrame("Frame", "ForeverAddonsLauncherFrameSecure", UIParent, template)
	panel.foreverSecurePanel=true
	_G.ForeverAddonsLauncherFrame=panel
	panel:SetSize(218, 120)
	panel:SetFrameStrata("DIALOG")
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	AddBackdrop(panel)
	panel.rows = {}
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -14)
	title:SetText("FOREVER ADDONS")
	title:SetTextColor(1, 0.82, 0)
	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButtonNoScripts,SecureHandlerClickTemplate")
	close:SetAttribute("_onclick",[[self:GetParent():Hide()]])
	close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
	panel:Hide()
	self.panel = panel
	if UISpecialFrames then table.insert(UISpecialFrames, "ForeverAddonsLauncherFrameSecure") end
	self:EnsurePanel()
	self:RefreshPanel()
	self:PlacePanel(panel)
	return panel
end

function launcher:Toggle()
	if Combat() then return end
	if #self:GetFamilyAddons() == 0 then return end
	local panel = self:EnsurePanel()
	if panel:IsShown() then panel:Hide(); return end
	self:RefreshPanel()
	self:PlacePanel(panel)
	panel:Show()
end

function launcher:EnsureButton(leadEntry)
	if not Minimap then return nil end
	local button = self.button
	if button and not button.foreverSecureFamily then button:Hide(); button=nil end
	if not button then
		button = CreateFrame("Button", "ForeverAddonsMinimapButtonSecure", Minimap,"SecureHandlerBaseTemplate")
		button.foreverSecureFamily=true
		_G.ForeverAddonsMinimapButton=button
		button:SetSize(32, 32)
		local icon = button:CreateTexture(nil, "BACKGROUND")
		icon:SetSize(22, 22)
		icon:SetPoint("CENTER", button, "CENTER")
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		button.foreverIconTexture = icon
		local border = button:CreateTexture(nil, "OVERLAY")
		border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
		border:SetSize(54, 54)
		border:SetPoint("TOPLEFT", button, "TOPLEFT")
	end
	-- Reuse the icon texture from a v1-v4 button, and remove its old F overlay.
	if not button.foreverIconTexture and button.GetRegions then
		for _, region in ipairs({ button:GetRegions() }) do
			if region.GetText and region:GetText() == "F" then region:Hide() end
			if region.GetTexture and
				(region:GetTexture() == "Interface\\Icons\\INV_Misc_Map_01"
					or (region:GetWidth() == 22 and region:GetHeight() == 22)) then
				button.foreverIconTexture = region
			end
		end
	end
	if not button.foreverIconTexture then
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetSize(22, 22)
		icon:SetPoint("CENTER", button, "CENTER")
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		button.foreverIconTexture = icon
	end
	button.foreverIconTexture:SetTexture(leadEntry and leadEntry.icon
		or "Interface\\Icons\\INV_Misc_QuestionMark")
	button.foreverLeadTitle = leadEntry and (leadEntry.title or leadEntry.id) or nil
	self.button = button
	button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local panel=self:EnsurePanel()
    button:SetFrameRef("launcher-panel",panel)
    button:SetAttribute("launcher-ignore-click",button.foreverIgnoreClick)
    if not button.foreverSecureToggle then
        button.foreverSecureToggle=true
        SecureHandlerWrapScript(button,"OnClick",button,[[
            if SecureCmdOptionParse("[combat]combat") then
                if not self:GetAttribute("launcher-ignore-click") then
                    local panel=self:GetFrameRef("launcher-panel")
                    if panel:IsShown() then panel:Hide() else panel:Show() end
                end
                return false
            end
        ]])
    end
    button:SetScript("PostClick", function(owner)
        if not Combat() and not owner.foreverIgnoreClick then launcher:Toggle() end
    end)
	button:SetScript("OnEnter", function(owner)
		if not GameTooltip then return end
		GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
		GameTooltip:SetText("Forever Addons", 1, 0.82, 0)
		if owner.foreverLeadTitle then
			GameTooltip:AddLine(launcher:GetFamilyDisplayText("top", "Top of list: %s", owner.foreverLeadTitle), 0.9, 0.8, 0.5)
		end
		GameTooltip:AddLine(launcher:GetFamilyDisplayText("open-family", "Click: open the family list"), 0.85, 0.85, 0.85)
		GameTooltip:AddLine(launcher:GetFamilyDisplayText("drag", "Drag: move around the minimap edge"), 0.75, 0.75, 0.75)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	self:InstallDrag(button)
	self:PlaceOnEdge(button, self.familyX, self.familyY)
	self:EnsureResizeHook()
	return button
end

function launcher:ConfigureExternalButton(entry)
	local button = entry.individualButton
	if not button then return nil end
	button.foreverEntry = entry
	if button.foreverLauncherOwnerID ~= entry.id then
		button.foreverLauncherOwnerID = entry.id
		button.foreverLauncherOriginalOnClick = button.GetScript and button:GetScript("OnClick")
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		if button.HookScript then
			button:HookScript("OnEnter", function(owner)
				if not GameTooltip or #launcher:GetSortedAddons() <= 1 then return end
				if GameTooltip:GetOwner() ~= owner then
					GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
					GameTooltip:SetText(owner.foreverEntry.title or owner.foreverEntry.id, 1, 0.82, 0)
				end
				GameTooltip:AddLine("Ctrl-click: return to Forever list", 0.85, 0.85, 0.85)
				GameTooltip:Show()
			end)
		end
		button:SetScript("OnClick", function(owner, mouseButton)
			local current = owner.foreverEntry
			if owner.foreverIgnoreClick or owner.ignoreClick then return end
			if Ctrl() and #launcher:GetSortedAddons() > 1 then
				launcher:SetDetached(current.id, false)
				return
			end
			if type(owner.foreverLauncherOriginalOnClick) == "function" then
				owner.foreverLauncherOriginalOnClick(owner, mouseButton)
			elseif type(current.open) == "function" then
				current.open()
			end
		end)
	end
	return button
end

function launcher:EnsureIndividualButton(entry)
	if entry.individualButton then return self:ConfigureExternalButton(entry) end
	if entry.generatedButton and not entry.generatedButton.foreverSecureClick then
        entry.generatedButton:Hide(); entry.generatedButton=nil
    end
    if entry.generatedButton then
        entry.generatedButton.foreverEntry=entry
        ConfigureSecureClick(entry.generatedButton,entry)
        return entry.generatedButton
    end
	if not Minimap then return nil end
	local safeID = string.gsub(entry.id, "[^%w]", "")
	local button = CreateFrame("Button", "ForeverAddonsIcon" .. safeID .. "Secure", Minimap,"SecureActionButtonTemplate,SecureHandlerBaseTemplate")
	_G["ForeverAddonsIcon" .. safeID]=button
	button:SetSize(31, 31)
	button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(22, 22)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.icon = icon
	button.foreverEntry = entry
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	ConfigureSecureClick(button,entry)
	button:SetScript("PostClick", function(owner, mouseButton)
		local current = owner.foreverEntry
		if owner.foreverIgnoreClick or owner:GetAttribute("launcher-ignore-click") then return end
		if Ctrl() and #launcher:GetSortedAddons() > 1 then
			launcher:SetDetached(current.id, false)
			return
		end
		if owner:GetAttribute("launcher-combat-click") then return end
		if type(current.individualClick) == "function" then
			current.individualClick(mouseButton)
		elseif type(current.open) == "function" then
			current.open()
		end
	end)
	button:SetScript("OnEnter", function(owner)
		local current = owner.foreverEntry
		if not GameTooltip then return end
		GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
		GameTooltip:SetText(current.title or current.id, 1, 0.82, 0)
		if current.subtitle then GameTooltip:AddLine(current.subtitle, 0.85, 0.85, 0.85) end
		GameTooltip:AddLine(current.individualHint or DisplayText(current, "open", "Click: open addon"), 0.85, 0.85, 0.85)
		if #launcher:GetSortedAddons() > 1 then
			GameTooltip:AddLine(DisplayText(current, "return", "Ctrl-click: return to Forever list"), 0.85, 0.85, 0.85)
		end
		GameTooltip:AddLine(DisplayText(current, "drag", "Drag: move around the minimap edge"), 0.75, 0.75, 0.75)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	entry.generatedButton = button
	self:InstallDrag(button, entry)
	self:PositionIndividual(entry)
	self:EnsureResizeHook()
	return button
end

function launcher:RefreshButtons()
	if Combat() then DeferLayout(); return end
	local all = self:GetSortedAddons()
	local multiple, familyCount, leadEntry = #all > 1, 0, nil
	for _, entry in ipairs(all) do
		local individual = not multiple or (entry.storage and entry.storage.detached)
		if entry.storage and entry.storage.iconHidden then
			if entry.generatedButton then entry.generatedButton:Hide() end
			if entry.individualButton then entry.individualButton:Hide() end
		elseif individual then
			local button = self:EnsureIndividualButton(entry)
			if entry.generatedButton then
				entry.generatedButton:SetShown(button == entry.generatedButton)
				entry.generatedButton.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
				self:PositionIndividual(entry)
			end
			if entry.individualButton then entry.individualButton:Show() end
		else
			familyCount = familyCount + 1
			if not leadEntry then leadEntry = entry end
			if entry.generatedButton then entry.generatedButton:Hide() end
			if entry.individualButton then entry.individualButton:Hide() end
		end
	end
	if multiple and familyCount > 0 then
		local button = self:EnsureButton(leadEntry)
		if button then button:Show() end
	elseif self.button then
		self.button:Hide()
	end
	if self.panel then self:RefreshPanel(); self:PlacePanel(self.panel) end
end

-- Visibility affects minimap presence only; registration and the full list stay.
function launcher:SetIconVisible(id, visible)
	local entry = self.addons[id]
	if not entry then return false end
	entry.storage.iconHidden = visible == false
	self:RefreshButtons()
	return true
end

function launcher:SetDetached(id, detached)
	local entry = self.addons[id]
	if not entry or #self:GetSortedAddons() <= 1 then return false end
	entry.storage.detached = detached and true or false
	self:RefreshButtons()
	return true
end

function launcher:RegisterAddon(id, data)
	if type(id) ~= "string" or type(data) ~= "table" then return false end
	local old = self.addons[id]
	data.id = id
	data.storage = type(data.storage) == "table" and data.storage or (old and old.storage) or {}
	if data.storage.detached == nil and data.defaultDetached ~= nil then
		data.storage.detached = data.defaultDetached and true or false
	end
	if old and old.generatedButton then
		data.generatedButton = old.generatedButton
		if data.individualButton and not Combat() then old.generatedButton:Hide() end
	end
	if not Combat() and old and old.individualButton and old.individualButton ~= data.individualButton then
		old.individualButton:Hide()
	end
	self.addons[id] = data
	if Combat() then DeferLayout(); return true end
	if data.individualButton then self:ConfigureExternalButton(data) end
	self:AdoptFamilyPosition(data.storage)
	self:AdoptPanelPosition(data.storage)
	self:AdoptListOrder(data.storage)
	self:RefreshButtons()
	return true
end

launcher.initialized = true
-- A v1 copy might have registered addons before this v2 copy loaded.
for _, entry in pairs(launcher.addons) do
	if type(entry.storage) ~= "table" then entry.storage = {} end
end
if next(launcher.addons) then launcher:RefreshButtons() end
