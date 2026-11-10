-- Local addition: fishing bar "Bobber zoom" toggle.
-- WoW's camera orbits the player and cannot be aimed at a world point, so this
-- zooms the camera in close along the current view. Camera Assist normally
-- leaves the camera pointed at the bobber, so the bobber stays in view.
-- Uses FF:CallCamera so the camera-assist hooks treat it as the addon's own call.
local FF = _G.ForeverFishing
local DEFAULT_ZOOM_DISTANCE = 3

function FF:GetBobberZoomDistance()
    local v = tonumber(self.db and self.db.bobberZoomDistance) or DEFAULT_ZOOM_DISTANCE
    return math.max(1, math.min(15, v))
end

function FF:SetBobberZoomDistance(value)
    if not self.db then return end
    self.db.bobberZoomDistance = math.max(1, math.min(15, math.floor((tonumber(value) or DEFAULT_ZOOM_DISTANCE) + 0.5)))
end

function FF:BobberZoomActive() return self.bobberZoomRestore ~= nil end

function FF:ToggleBobberZoom()
    if self:BobberZoomActive() then return self:EndBobberZoom() end
    if type(GetCameraZoom) ~= "function" or type(CameraZoomIn) ~= "function" then return false end
    local ok, current = pcall(GetCameraZoom)
    if not ok or type(current) ~= "number" or (issecretvalue and issecretvalue(current)) then return false end
    local target = self:GetBobberZoomDistance()
    local delta = current - target
    if delta <= 0.1 then return false end -- already at least this close
    self.bobberZoomRestore = current
    self:CallCamera(CameraZoomIn, delta)
    self:RefreshBobberZoomButton()
    return true
end

function FF:EndBobberZoom()
    local restore = self.bobberZoomRestore
    if not restore then return false end
    self.bobberZoomRestore = nil
    local ok, current = pcall(GetCameraZoom)
    if ok and type(current) == "number" and restore > current and type(CameraZoomOut) == "function" then
        self:CallCamera(CameraZoomOut, restore - current)
    end
    self:RefreshBobberZoomButton()
    return true
end

function FF:RefreshBobberZoomButton()
    local button = self.bobberZoomButton
    if not button then return end
    local on = self:BobberZoomActive()
    if button.procGlow then
        if on then button.procGlow:Show() else button.procGlow:Hide() end
    end
end

function FF:SetupBobberZoomButton(button)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function() self:ToggleBobberZoom() end)
    button:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText("Bobber zoom")
        GameTooltip:AddLine(self:BobberZoomActive() and "Click to return the camera to its previous distance."
            or "Click to zoom the camera in close on your bobber.", 1, 1, 1, true)
        GameTooltip:AddLine("Restores automatically when you stop fishing.", 0.76, 0.82, 0.8, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Put the camera back when the fishing channel ends or the player leaves the world.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
watcher:RegisterEvent("PLAYER_LEAVING_WORLD")
watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" and unit ~= "player" then return end
    if FF:BobberZoomActive() then FF:EndBobberZoom() end
end)
