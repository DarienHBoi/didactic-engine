-- Minimap bell pip: a small draggable button on the minimap edge. Click toggles the board, drag moves it around the edge.
-- Created at PLAYER_LOGIN (the saved variable is ready by then). OnUpdate exists only while dragging.
local addonName, RB = ...

local Pip = {}
RB.Pip = Pip

local BELL = "Interface\\AddOns\\RingTheBell\\Media\\Bell"  -- our own Media/Bell.tga
local button

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end

local function commas(n)
    if type(n) ~= "number" then return tostring(n) end
    local s = string.format("%d", math.floor(n + 0.5))
    local sign, digits = s:match("^(-?)(%d+)$")
    if not digits then return s end
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return sign .. (digits:gsub("^,", ""))
end

local function place()
    if not button or not Minimap then return end
    local angle = (RB.db and RB.db.pip and RB.db.pip.angle) or 200
    local radius = ((Minimap:GetWidth() or 140) / 2) + 5
    local a = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
end

local function onDragUpdate()
    local mx, my = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    local deg = math.deg(atan2(my - cy * scale, mx - cx * scale))
    if deg < 0 then deg = deg + 360 end
    if RB.db and RB.db.pip then RB.db.pip.angle = deg end
    place()
end

function Pip.refresh()
    if not button then return end
    local o = RB.db and RB.db.options
    button:SetShown(not (o and o.pip == false))
    place()
end

local function create()
    if button or not Minimap then return end
    local b = CreateFrame("Button", "RingTheBellPip", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1); icon:SetTexture(BELL)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", function() if RB.Board and RB.Board.toggle then RB.Board.toggle() end end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil); onDragUpdate() end)
    local function stopDrag(self) self:SetScript("OnUpdate", nil) end
    b:SetScript("OnHide", stopDrag)
    b:SetScript("OnMouseUp", stopDrag)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Ring the Bell")
        local rec = RB.db and RB.db.record
        if rec then
            local who = type(rec.player) == "string" and (rec.player:match("^([^%-]+)") or rec.player) or "?"
            GameTooltip:AddLine("Record: " .. commas(rec.amount) .. " " .. tostring(rec.spell or "?") .. " (" .. who .. ")", 1, 1, 1)
        else
            GameTooltip:AddLine("No record yet", 1, 1, 1)
        end
        GameTooltip:AddLine("Click: open the board. Drag: move this button.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button = b
    Pip.refresh()
end

local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
f:SetScript("OnEvent", function() create() end)
