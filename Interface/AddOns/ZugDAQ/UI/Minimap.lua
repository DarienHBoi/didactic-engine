local _, ns = ...

-- minimap button through LibDBIcon, like most addons, so button-collector addons pick it up too.
-- Left-click opens the window, right-click starts or stops a farming session.

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
local NAME = "ZugDAQ"

local function tooltip(tip)
    tip:AddLine("ZugDAQ", 1, 0.82, 0)
    tip:AddDoubleLine("All characters", ns.Money(ns.TotalGold()), 1, 1, 1, 1, 1, 1)
    local today = ns.Totals({ ns.Today() })
    local week = ns.Totals(ns.LastDays(7))
    tip:AddDoubleLine("Today", ns.MoneyColored(today.net), 1, 1, 1, 1, 1, 1)
    tip:AddDoubleLine("This week", ns.MoneyColored(week.net), 1, 1, 1, 1, 1, 1)
    if week.skills > 0 then
        tip:AddDoubleLine("Skills & training (week)", ns.Money(week.skills), 0.5, 0.5, 1, 1, 1, 1)
    end
    local s = ns.ActiveSession()
    if s then
        local secs = ns.SessionElapsed(s)
        local value = ns.SessionValue(s)
        local gph = ns.PerHour(value, secs)
        tip:AddLine(" ")
        tip:AddLine((s.runningSince and "Farming: " or "Paused: ") .. s.route, 0.4, 1, 0.4)
        tip:AddDoubleLine(ns.Duration(secs), ns.Money(value) .. (gph and ("  (" .. ns.Money(gph) .. "/h)") or ""),
            1, 1, 1, 1, 1, 1)
    end
    local ok, actions = pcall(ns.Actions)
    if ok and #actions > 0 then
        tip:AddLine(" ")
        tip:AddLine("Next up", 1, 0.82, 0)
        for i = 1, math.min(3, #actions) do
            local a = actions[i]
            local style = ns.ACTION_STYLE[a.verb]
            tip:AddDoubleLine((style and style.color or "") .. a.verb .. "|r " .. a.title, a.goldText or "", 1, 1, 1, 1, 1, 1)
        end
    end
    tip:AddLine(" ")
    tip:AddLine("Left-click: open ZugDAQ", 0.6, 0.6, 0.6)
    tip:AddLine(s and "Right-click: stop and save the farming run" or "Right-click: start farming here", 0.6, 0.6, 0.6)
end

local function onClick(_, button)
    if button == "RightButton" then
        if ns.ActiveSession() then ns.StopSession() else ns.StartSession() end
    else
        ns.ToggleFrame()
    end
end

function ns.ToggleMinimapButton()
    local cfg = ns.settings.minimap
    cfg.hide = not cfg.hide
    if DBIcon then
        if cfg.hide then DBIcon:Hide(NAME) else DBIcon:Show(NAME) end
    end
    ns.Print("minimap button %s. /zug minimap to change it back.", cfg.hide and "hidden" or "shown")
end

ns.OnLogin(function()
    if not (LDB and DBIcon) then return end
    local launcher = LDB:NewDataObject(NAME, {
        type = "launcher",
        label = "ZugDAQ",
        icon = "Interface\\Icons\\INV_Misc_Coin_02",
        OnClick = onClick,
        OnTooltipShow = tooltip,
    })
    DBIcon:Register(NAME, launcher, ns.settings.minimap)
end)
