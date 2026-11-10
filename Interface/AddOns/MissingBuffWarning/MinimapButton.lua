-- Minimap button for Missing Buff Warning (self-contained; click: open options, drag: move, /mbwmap: hide/show).
local CFG = {
    frameName = "MissingBuffWarningMinimapButton",
    db = "MissingBuffWarningDB",
    icon = "Interface\\Icons\\Spell_Holy_InnerFire",
    title = "Missing Buff Warning",
    hint = "open options",
    slash = "/mbwmap",
    onClick = function() SlashCmdList["MISSINGBUFFWARNING"]("") end,
}

local button

local function settings()
    local db = _G[CFG.db]
    if type(db) ~= "table" then db = {}; _G[CFG.db] = db end
    db.minimap = type(db.minimap) == "table" and db.minimap or {}
    if type(db.minimap.angle) ~= "number" then db.minimap.angle = 200 end
    if type(db.minimap.hidden) ~= "boolean" then db.minimap.hidden = false end
    return db.minimap
end

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end

local function place()
    if not button then return end
    local a = math.rad(settings().angle)
    local r = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function onDragUpdate()
    local mx, my = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    local deg = math.deg(atan2(my - cy * scale, mx - cx * scale))
    if deg < 0 then deg = deg + 360 end
    settings().angle = deg
    place()
end

local function create()
    if button or not Minimap then return end
    button = CreateFrame("Button", CFG.frameName, Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(CFG.icon)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", function()
        local ok, err = pcall(CFG.onClick)
        if not ok then print(CFG.title .. ": " .. tostring(err)) end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(CFG.title)
        GameTooltip:AddLine("Click: " .. CFG.hint, 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    place()
    button:SetShown(not settings().hidden)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", create)

_G["SLASH_" .. CFG.frameName:upper() .. "1"] = CFG.slash
SlashCmdList[CFG.frameName:upper()] = function()
    local s = settings()
    s.hidden = not s.hidden
    if button then button:SetShown(not s.hidden) end
    print(CFG.title .. " minimap button " .. (s.hidden and "hidden" or "shown"))
end
