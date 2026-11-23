local _, ns = ...

-- Our own small rename box. Blizzard's StaticPopup dialogs are shared with the game's own confirmations (delete item,
-- bind on pickup...); an addon showing one taints them, and the game then blocks its own buttons and blames us.
local renameBox
local function showRename(route)
    if not renameBox then
        local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        f:SetSize(320, 110)
        f:SetPoint("CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        ns.Backdrop(f)
        f.label = ns.Label(f, "GameFontNormal")
        f.label:SetPoint("TOP", 0, -14)
        f.label:SetWidth(290)
        local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        box:SetSize(260, 22)
        box:SetPoint("TOP", 0, -40)
        box:SetAutoFocus(true)
        f.box = box
        local function accept()
            local text = strtrim(box:GetText() or "")
            if text ~= "" and f.route then ns.RenameRoute(f.route, text) end
            f:Hide()
        end
        box:SetScript("OnEnterPressed", accept)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        local ok = ns.Button(f, ACCEPT or "Accept", 100, accept)
        ok:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 12)
        local cancel = ns.Button(f, CANCEL or "Cancel", 100, function() f:Hide() end)
        cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 12)
        renameBox = f
    end
    renameBox.route = route
    renameBox.label:SetText(string.format("Rename route \"%s\" to:", route))
    renameBox.box:SetText(route or "")
    renameBox:Show()
    renameBox.box:SetFocus()
    renameBox.box:HighlightText()
end

local function itemsTooltip(tip, items, duration)
    local top = ns.TopItems(items, 12)
    if #top == 0 then return end
    tip:AddLine(" ")
    tip:AddLine("Top loot (today's prices)", 1, 0.82, 0)
    for _, it in ipairs(top) do
        local label = ns.ItemLabel(it.itemID)
        local right = ns.Money(it.value)
        local gph = duration and ns.PerHour(it.value, duration)
        if gph then right = right .. " |cffaaaaaa(" .. ns.Money(gph) .. "/h)|r" end
        tip:AddDoubleLine(string.format("%s x%d", label, it.count), right, 1, 1, 1, 1, 1, 1)
    end
end

ns.RegisterPage("farming", "Farming", function(page)
    local W = ns.PAGE_WIDTH
    page.view = "routes"

    local routeLabel = ns.Label(page, "GameFontNormal", "Route:")
    routeLabel:SetPoint("TOPLEFT", 0, -4)
    local routeBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    routeBox:SetSize(200, 20)
    routeBox:SetPoint("LEFT", routeLabel, "RIGHT", 10, 0)
    routeBox:SetAutoFocus(false)
    routeBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    routeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    routeBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Name the route you're about to farm.")
        GameTooltip:AddLine("Leave it empty to use the zone name. Click a route below to reuse its name.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    routeBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local startBtn = ns.Button(page, "Start", 70, function()
        local text = strtrim(routeBox:GetText() or "")
        ns.StartSession(text ~= "" and text or nil)
        routeBox:ClearFocus()
    end)
    startBtn:SetPoint("LEFT", routeBox, "RIGHT", 8, 0)
    local pauseBtn = ns.Button(page, "Pause", 70, function()
        local s = ns.ActiveSession()
        if s and s.runningSince then ns.PauseSession() else ns.ResumeSession() end
    end)
    pauseBtn:SetPoint("LEFT", startBtn, "RIGHT", 4, 0)
    local stopBtn = ns.Button(page, "Stop & save", 90, function() ns.StopSession() end)
    stopBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 4, 0)

    local status = ns.Label(page, "GameFontHighlight", "", "LEFT")
    status:SetPoint("TOPLEFT", 0, -32)
    status:SetWidth(W)

    local routes = ns.CreateTable(page, {
        { title = "Route", width = 220, text = function(r) return r.route end, sort = function(r) return r.route end, defaultAsc = true },
        { title = "Runs", width = 50, align = "RIGHT", text = function(r) return r.runs end, sort = function(r) return r.runs end },
        { title = "Time", width = 80, align = "RIGHT", text = function(r) return ns.Duration(r.time) end, sort = function(r) return r.time end },
        { title = "Earned", width = 100, align = "RIGHT", text = function(r) return ns.Money(r.value) end, sort = function(r) return r.value end },
        { title = "Gold / hour", width = 100, align = "RIGHT", text = function(r) return r.gph and ns.Money(r.gph) or "-" end, sort = function(r) return r.gph end },
        { title = "Best run /h", width = 100, align = "RIGHT", text = function(r) return r.best and ns.Money(r.best) or "-" end, sort = function(r) return r.best end },
        { title = "Last run", width = 90, align = "RIGHT", text = function(r) return date("%d %b", r.last) end, sort = function(r) return r.last end },
    }, {
        rows = 18, sortCol = 5,
        empty = "No farming runs yet. Name a route and press Start, or type /zug farm start.",
        onEnter = function(r, row)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.route, 1, 0.82, 0)
            GameTooltip:AddDoubleLine("Coin looted", ns.Money(r.coin), 1, 1, 1, 1, 1, 1)
            itemsTooltip(GameTooltip, r.items, r.time)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click: farm this route next.  Right-click: rename.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end,
        onClick = function(r, button)
            if button == "RightButton" then
                showRename(r.route)
            else
                routeBox:SetText(r.route)
            end
        end,
    })
    routes:SetPoint("TOPLEFT", 0, -58)
    routes:SetWidth(W)

    local sessions = ns.CreateTable(page, {
        { title = "Date", width = 100, text = function(r) return date("%d %b %H:%M", r.s.started) end, sort = function(r) return r.s.started end },
        { title = "Route", width = 180, text = function(r) return r.s.route end, sort = function(r) return r.s.route end, defaultAsc = true },
        { title = "Character", width = 90, text = function(r) return (r.s.char or ""):match("^[^-]+") or "" end, sort = function(r) return r.s.char or "" end, defaultAsc = true },
        { title = "Time", width = 70, align = "RIGHT", text = function(r) return ns.Duration(r.s.duration) end, sort = function(r) return r.s.duration end },
        { title = "Coin", width = 80, align = "RIGHT", text = function(r) return ns.Money(r.s.coin) end, sort = function(r) return r.s.coin end },
        { title = "Total", width = 90, align = "RIGHT", text = function(r) return ns.Money(r.value) end, sort = function(r) return r.value end },
        { title = "Gold / hour", width = 100, align = "RIGHT", text = function(r) return r.gph and ns.Money(r.gph) or "-" end, sort = function(r) return r.gph end },
    }, {
        rows = 18, sortCol = 1,
        empty = "No farming runs yet.",
        onEnter = function(r, row)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.s.route, 1, 0.82, 0)
            GameTooltip:AddLine(table.concat(r.s.zones or {}, ", "), 0.8, 0.8, 0.8, true)
            GameTooltip:AddDoubleLine("Value when it ended", ns.Money(r.s.valueAtEnd), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Value at today's prices", ns.Money(r.value), 1, 1, 1, 1, 1, 1)
            itemsTooltip(GameTooltip, r.s.items, r.s.duration)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Shift-right-click: delete this run.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end,
        onClick = function(r, button)
            if button == "RightButton" and IsShiftKeyDown() then
                for i, s in ipairs(ns.db.sessions) do
                    if s == r.s then ns.DeleteSession(i) break end
                end
            end
        end,
    })
    sessions:SetPoint("TOPLEFT", 0, -58)
    sessions:SetWidth(W)

    function page:Refresh()
        local s = ns.ActiveSession()
        if s then
            local elapsed = ns.SessionElapsed(s)
            local value = ns.SessionValue(s)
            local gph = ns.PerHour(value, elapsed)
            status:SetText(string.format("%s |cffffffff%s|r   %s   %s%s",
                s.runningSince and "|cff40ff40Farming|r" or "|cffffd200Paused|r", s.route, ns.Duration(elapsed),
                ns.Money(value), gph and ("   " .. ns.Money(gph) .. " per hour") or ""))
            pauseBtn:SetText(s.runningSince and "Pause" or "Resume")
            startBtn:Disable()
            pauseBtn:Enable()
            stopBtn:Enable()
        else
            status:SetText("|cffaaaaaaNo session running.|r Loot and coin are only counted while one is.")
            pauseBtn:SetText("Pause")
            startBtn:Enable()
            pauseBtn:Disable()
            stopBtn:Disable()
        end

        routes:SetShown(self.view == "routes")
        sessions:SetShown(self.view == "sessions")
        if self.view == "routes" then
            routes:SetData(ns.RouteStats())
        else
            local rows = {}
            for _, sess in ipairs(ns.db.sessions) do
                local value = ns.SessionValue(sess)
                rows[#rows + 1] = { s = sess, value = value, gph = ns.PerHour(value, sess.duration) }
            end
            sessions:SetData(rows)
        end
    end

    -- keep the running clock moving while the tab is open
    local elapsed = 0
    page:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        local s = ns.ActiveSession()
        if s and s.runningSince then
            local value = ns.SessionValue(s)
            local secs = ns.SessionElapsed(s)
            local gph = ns.PerHour(value, secs)
            status:SetText(string.format("|cff40ff40Farming|r |cffffffff%s|r   %s   %s%s", s.route, ns.Duration(secs),
                ns.Money(value), gph and ("   " .. ns.Money(gph) .. " per hour") or ""))
        end
    end)
end)

ns.Listen("SESSION", ns.RefreshVisible)
