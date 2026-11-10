-- Graphics Pip: minimap button + small menu that pushes graphics CVars.
local SetCVarFn = (C_CVar and C_CVar.SetCVar) or SetCVar
local GetCVarFn = (C_CVar and C_CVar.GetCVar) or GetCVar

-- name, label, min, max, step, preset (the values you pasted)
local SETTINGS = {
    { "groundEffectDensity",         "Ground effect density (default 48)",  0, 256,  1,   256 },
    { "groundEffectFade",            "Ground effect fade (default 70)",     0, 500,  1,   370 },
    { "groundEffectDist",            "Ground effect distance (default 200)", 0, 1000, 1,   500 },
    { "HDROutput",                   "HDR output (0 off, 1 on)", 0, 1,  1,   1 },
    { "HDRFactor",                   "HDR factor",             0, 3,    0.1, 1 },
    { "lodObjectFadeScale",          "Object fade scale",      0, 300,  1,   200 },
    { "lodObjectCullSize",           "Object cull size",       0, 50,   1,   8 },
    { "terrainLodDist",              "Terrain LOD distance",   0, 2000, 10,  1000 },
    { "ResampleAlwaysSharpen",       "Always sharpen",         0, 1,    1,   1 },
    { "reflectionMode",              "Reflection mode",        0, 3,    1,   3 },
    { "weatherDensity",              "Weather density",        0, 3,    1,   3 },
    { "cameraDistanceMaxZoomFactor", "Max camera zoom factor", 1, 4,    0.1, 4.0 },
}

local db
local function Read(name)
    local ok, v = pcall(GetCVarFn, name)
    if ok and v ~= nil then return tonumber(v) end
end
local function Push(name, value)
    local ok = pcall(SetCVarFn, name, tostring(value))
    if ok then db.values[name] = value end
    return ok
end

local rows = {}
local function Fmt(step, v) return string.format(step < 1 and "%.1f" or "%d", v) end
local function RefreshRows()
    for _, r in ipairs(rows) do
        local v = Read(r.name)
        r.slider:SetEnabled(v ~= nil)
        if v ~= nil then
            r.updating = true; r.slider:SetValue(v); r.updating = false
            r.value:SetText(Fmt(r.step, v))
        else
            r.value:SetText("n/a")
        end
    end
end

local menu
local function BuildMenu()
    menu = CreateFrame("Frame", "GraphicsPipMenu", UIParent, "BackdropTemplate")
    menu:SetSize(320, 64 + #SETTINGS * 44 + 40)
    menu:SetPoint("CENTER")
    menu:SetFrameStrata("DIALOG"); menu:SetClampedToScreen(true)
    menu:SetMovable(true); menu:EnableMouse(true)
    menu:RegisterForDrag("LeftButton")
    menu:SetScript("OnDragStart", menu.StartMoving)
    menu:SetScript("OnDragStop", menu.StopMovingOrSizing)
    menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    menu:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    menu:Hide()
    tinsert(UISpecialFrames, "GraphicsPipMenu")

    local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12); title:SetText("Graphics Pip")
    local close = CreateFrame("Button", nil, menu, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    for i, s in ipairs(SETTINGS) do
        local name, label, lo, hi, step = s[1], s[2], s[3], s[4], s[5]
        local y = -40 - (i - 1) * 44
        local fs = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 16, y); fs:SetText(label)
        local val = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        val:SetPoint("TOPRIGHT", -16, y)
        local sl = CreateFrame("Slider", nil, menu, "MinimalSliderTemplate")
        sl:SetPoint("TOPLEFT", 16, y - 16); sl:SetSize(288, 14)
        sl:SetMinMaxValues(lo, hi); sl:SetValueStep(step); sl:SetObeyStepOnDrag(true)
        local row = { name = name, step = step, slider = sl, value = val }
        sl:SetScript("OnValueChanged", function(_, v)
            if row.updating then return end
            if step >= 1 then v = math.floor(v + 0.5) else v = math.floor(v * 10 + 0.5) / 10 end
            val:SetText(Fmt(step, v))
            Push(name, v)
        end)
        rows[#rows + 1] = row
    end

    local by = 14
    local function Btn(text, x, w, fn)
        local b = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
        b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", x, by); b:SetText(text)
        b:SetScript("OnClick", fn)
        return b
    end
    Btn("My preset", 14, 90, function()
        for _, s in ipairs(SETTINGS) do Push(s[1], s[6]) end
        RefreshRows()
    end)
    Btn("Restore originals", 108, 110, function()
        for name, v in pairs(db.originals) do Push(name, v) end
        RefreshRows()
    end)
    local cb = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
    cb:SetPoint("BOTTOMLEFT", 222, by - 3); cb:SetSize(24, 24)
    cb:SetChecked(db.reapply)
    cb:SetScript("OnClick", function(b) db.reapply = b:GetChecked() and true or false end)
    local cbt = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbt:SetPoint("LEFT", cb, "RIGHT", 0, 1); cbt:SetText("Reapply at login")
    menu:SetScript("OnShow", RefreshRows)
end

local function ToggleMenu()
    if not menu then BuildMenu() end
    menu:SetShown(not menu:IsShown())
end

-- Minimap button (round minimap assumed)
local function PlaceButton(btn)
    local a = math.rad(db.angle or 215)
    local r = (Minimap:GetWidth() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function BuildButton()
    local b = CreateFrame("Button", "GraphicsPipButton", Minimap)
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp"); b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", ToggleMenu)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Graphics Pip")
        GameTooltip:AddLine("Click: open graphics menu. Drag: move around the minimap.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            db.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            PlaceButton(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    PlaceButton(b)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    GraphicsPipDB = GraphicsPipDB or {}
    db = GraphicsPipDB
    db.values = db.values or {}
    db.originals = db.originals or {}
    if db.reapply == nil then db.reapply = false end
    for _, s in ipairs(SETTINGS) do
        if db.originals[s[1]] == nil then db.originals[s[1]] = Read(s[1]) end
    end
    if db.reapply then
        for name, v in pairs(db.values) do pcall(SetCVarFn, name, tostring(v)) end
    end
    BuildButton()
    SLASH_GRAPHICSPIP1 = "/gpip"
    SlashCmdList.GRAPHICSPIP = ToggleMenu
end)
