local _, ns = ...

-- small movable tracker shown while a farming session runs

local live

local function build()
    live = CreateFrame("Frame", "ZugDAQLiveFrame", UIParent, "BackdropTemplate")
    live:SetSize(230, 86)
    live:SetFrameStrata("MEDIUM")
    live:SetClampedToScreen(true)
    live:SetMovable(true)
    live:EnableMouse(true)
    live:RegisterForDrag("LeftButton")
    live:SetScript("OnDragStart", live.StartMoving)
    live:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.settings.livePos = { point, relPoint, x, y }
    end)
    ns.Backdrop(live, 0.05, 0.05, 0.07, 0.85)
    local pos = ns.settings.livePos
    if pos then live:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else live:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120) end

    live.title = ns.Label(live, "GameFontNormal", "", "LEFT")
    live.title:SetPoint("TOPLEFT", 8, -7)
    live.title:SetWidth(214)
    live.title:SetWordWrap(false)
    live.body = ns.Label(live, "GameFontHighlightSmall", "", "LEFT")
    live.body:SetPoint("TOPLEFT", 8, -24)
    live.body:SetWidth(214)
    live.body:SetSpacing(2)

    local pause = ns.Button(live, "Pause", 70, function()
        local s = ns.ActiveSession()
        if s and s.runningSince then ns.PauseSession() else ns.ResumeSession() end
    end)
    pause:SetPoint("BOTTOMLEFT", 6, 5)
    pause:SetHeight(18)
    live.pause = pause
    local stop = ns.Button(live, "Stop & save", 90, function() ns.StopSession() end)
    stop:SetPoint("LEFT", pause, "RIGHT", 4, 0)
    stop:SetHeight(18)
    local open = ns.Button(live, "...", 30, function() ns.ToggleFrame("farming") end)
    open:SetPoint("LEFT", stop, "RIGHT", 4, 0)
    open:SetHeight(18)

    live:SetScript("OnEnter", function(self)
        local s = ns.ActiveSession()
        if not s then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Loot this session", 1, 0.82, 0)
        GameTooltip:AddDoubleLine("Coin", ns.Money(s.coin), 1, 1, 1, 1, 1, 1)
        for _, it in ipairs(ns.TopItems(s.items, 12)) do
            GameTooltip:AddDoubleLine(string.format("%s x%d", ns.ItemLabel(it.itemID), it.count), ns.Money(it.value), 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    live:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local acc = 0
    live:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        self:Update()
    end)

    function live:Update()
        local s = ns.ActiveSession()
        if not s then return end
        local secs = ns.SessionElapsed(s)
        local value, items = ns.SessionValue(s)
        local gph = ns.PerHour(value, secs)
        self.title:SetText((s.runningSince and "|cff40ff40" or "|cffffd200") .. s.route .. "|r")
        self.body:SetText(string.format("%s%s   %s\nItems %s   Coin %s",
            ns.Duration(secs), s.runningSince and "" or " (paused)",
            gph and (ns.Money(gph) .. "/h") or "", ns.Money(items), ns.Money(s.coin)))
        self.pause:SetText(s.runningSince and "Pause" or "Resume")
    end
end

function ns.UpdateLiveFrame()
    local show = ns.settings.liveShown and ns.ActiveSession() ~= nil
    if show and not live then build() end
    if not live then return end
    live:SetShown(show)
    if show then live:Update() end
end

ns.Listen("SESSION", ns.UpdateLiveFrame)
ns.OnLogin(function() C_Timer.After(1, ns.UpdateLiveFrame) end)
