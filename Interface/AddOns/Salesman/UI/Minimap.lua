local _, S = ...
S.UI = S.UI or {}

-- Round minimap button: click toggles the window, drag moves it around the minimap edge.
local button

local function place()
    if not button then return end
    local radius = (Minimap:GetWidth() / 2) + 5
    local x, y = S.MinimapMath.position(S.DB.global.minimapAngle, radius)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function onDragUpdate()
    local mx, my = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    S.DB.global.minimapAngle = S.MinimapMath.angleFromCursor(cx * scale, cy * scale, mx, my)
    place()
end

function S.UI.updateBadge()
    if not button or not button.badge then return end
    local n = (S.DB and S.DB.char and S.Customers.unreadCount(S.DB.char)) or 0
    button.badge:SetText(n > 0 and tostring(n) or "")
end

function S.UI.setMinimapShown(shown)
    S.DB.global.minimapHidden = not shown
    if button then button:SetShown(shown) end
end

function S.UI.initMinimapButton()
    if button or not Minimap then return end
    button = CreateFrame("Button", "SalesmanMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\Trade_Engraving")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.badge = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    button.badge:SetPoint("TOPRIGHT", 6, 6)
    button.badge:SetTextColor(1, 0.25, 0.25)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function() S.UI.toggle() end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Salesman")
        GameTooltip:AddLine("Click: open window", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
        local n = (S.DB and S.DB.char and S.Customers.unreadCount(S.DB.char)) or 0
        if n > 0 then GameTooltip:AddLine(n .. " unread customer(s)", 1, 0.82, 0) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    place()
    button:SetShown(not S.DB.global.minimapHidden)
    S.UI.updateBadge()
end
