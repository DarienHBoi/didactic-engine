-- Game side: minimap button, icon panel, hiding of the other addons' own buttons, /nk.
local ADDON, NK = ...
local L = NK.Logic

local db, button, panel, hider
local CELL, PAD, MAX_COLS = 36, 6, 4
local FOOT = 20 -- strip under the icon grid for the settings cog
local GOLD = { 1, 0.82, 0 }

local function say(msg)
    msg = "|cffffd100NectarKit:|r " .. tostring(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    else
        print(msg)
    end
end

local function darkGold(f)
    if not f.SetBackdrop then return end
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.07, 0.07, 0.065, 0.97)
    f:SetBackdropBorderColor(0.9, 0.72, 0.22, 1)
end

NK.say, NK.darkGold, NK.getDB = say, darkGold, function() return db end

-- Module API (global, safe to call at any time) ------------------------------------
-- NectarKit_RegisterModule(addon, key, label, default, onToggle) -> current on/off state
-- NectarKit_IsModuleOn(addon, key) -> boolean
-- Add-ons that load before NectarKit can append { addon=, key=, label=, default=, onToggle= } to the global
-- table NectarKit_Queue instead; it is drained at login.
NK.modules = L.newModules(function() return db end, function(addon, key, err)
    say("module " .. tostring(addon) .. "." .. tostring(key) .. " callback failed: " .. tostring(err))
end)

function NectarKit_RegisterModule(addon, key, label, default, onToggle)
    local ok, state = pcall(NK.modules.register, NK.modules, addon, key, label, default, onToggle)
    if NK.RefreshOptions then pcall(NK.RefreshOptions) end -- a late registration shows up in an open window
    return ok and state or false
end

function NectarKit_IsModuleOn(addon, key)
    local ok, state = pcall(NK.modules.isOn, NK.modules, addon, key)
    return ok and state or false
end

-- Panel -----------------------------------------------------------------

local function buildIcon(entry, index)
    local b = CreateFrame("Button", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(CELL, CELL)
    b.entry = entry
    if b.SetBackdrop then
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        b:SetBackdropColor(0.12, 0.115, 0.105, 0.98)
        b:SetBackdropBorderColor(0.48, 0.40, 0.27, 1)
    end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3)
    b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon:SetTexture(L.resolveIcon(entry, L.pickMetadata(_G)))
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(entry.title, GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine(entry.slash, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function()
        panel:Hide()
        local ok, err = L.runEntry(entry, SlashCmdList)
        if not ok then say(entry.title .. ": " .. tostring(err)) end
    end)
    return b
end

local function buildPanel()
    if panel then return end
    panel = CreateFrame("Frame", "NectarKitPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetScale(db.scale)
    darkGold(panel)
    local list = L.visibleEntries(NK.Entries, L.pickIsLoaded(_G), SlashCmdList)
    local lay = L.layout(#list, MAX_COLS, CELL, PAD)
    panel:SetSize(lay.width, lay.height + FOOT)
    if #list == 0 then
        local t = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        t:SetPoint("CENTER")
        t:SetText("No addons")
    end
    for i, entry in ipairs(list) do
        local b = buildIcon(entry, i)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", lay[i].x, lay[i].y)
    end
    local cog = CreateFrame("Button", "NectarKitSettingsButton", panel)
    cog:SetSize(16, 16)
    cog:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, 4)
    cog.icon = cog:CreateTexture(nil, "ARTWORK")
    cog.icon:SetAllPoints()
    cog.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    cog.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    cog:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    cog:RegisterForClicks("LeftButtonUp")
    cog:SetScript("OnClick", function()
        panel:Hide()
        NK.ToggleOptions()
    end)
    cog:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Settings", GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine("/nk options", 1, 1, 1)
        GameTooltip:Show()
    end)
    cog:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(UISpecialFrames, "NectarKitPanel") -- Escape closes it
    panel:Hide()
end

local function placePanel()
    local bx, by = button:GetCenter()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local p, rel = L.anchorFor(bx or 0, by or 0, sw, sh)
    panel:ClearAllPoints()
    panel:SetPoint(p, button, rel, 0, 0)
end

local function toggle()
    if not db or not button then return end
    buildPanel()
    if panel:IsShown() then
        panel:Hide()
    else
        placePanel()
        panel:Show()
    end
end

-- Minimap button -------------------------------------------------------

local function placeButton()
    local radius = (Minimap:GetWidth() / 2) + 5
    local x, y = L.position(db.angle, radius)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function onDragUpdate()
    local mx, my = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    db.angle = L.angleFromCursor(cx * scale, cy * scale, mx, my)
    placeButton()
end

local function buildButton()
    if button or not Minimap then return end
    button = CreateFrame("Button", "NectarKitMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", toggle)
    button:SetScript("OnDragStart", function(self)
        if panel then panel:Hide() end
        self:SetScript("OnUpdate", onDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("NectarKit", GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine("Click: open the addon drawer", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    placeButton()
end

-- Folding in the old buttons -----------------------------------------------

local function applyHiding()
    if not hider then
        hider = L.newHider(NK.Entries, function(name) return _G[name] end)
    end
    hider:apply(db.hideButtons)
end

local HIDE_DELAYS = { 1, 3, 6, 12 } -- some addons build their button late; every pass is idempotent

local function scheduleHiding()
    if not db.hideButtons then return end
    if C_Timer and C_Timer.After then
        for _, sec in ipairs(HIDE_DELAYS) do C_Timer.After(sec, applyHiding) end
    else
        applyHiding()
    end
end

-- Events and /nk -------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        db = L.initDB(NectarKitDB)
        NectarKitDB = db
        L.drainQueue(NK.modules, _G.NectarKit_Queue)
    elseif event == "PLAYER_LOGIN" and db then
        pcall(NK.captureBaseline)
        L.drainQueue(NK.modules, _G.NectarKit_Queue)
        NK.modules:login()
        buildButton()
        scheduleHiding()
    end
end)

local HELP = "/nk opens the drawer. /nk options opens the settings. /nk buttons [on|off] hides or restores the old minimap buttons. /nk scale 0.6-1.6. /nk perf lists the heaviest addons."

SLASH_NECTARKIT1 = "/nk"
SlashCmdList["NECTARKIT"] = function(msg)
    if not db then return end
    local cmd, arg = L.parseCommand(msg)
    if cmd == "" then
        toggle()
    elseif cmd == "options" or cmd == "settings" or cmd == "config" then
        if panel then panel:Hide() end
        NK.ToggleOptions()
    elseif cmd == "buttons" then
        db.hideButtons = L.parseSwitch(arg, db.hideButtons)
        applyHiding()
        say("hiding the other addons' minimap buttons: " .. (db.hideButtons and "on" or "off"))
        if db.hideButtons then scheduleHiding() end
    elseif cmd == "scale" then
        local n = tonumber(arg)
        if n then
            db.scale = L.clampScale(n)
            if panel then panel:SetScale(db.scale) end
            say("scale " .. db.scale)
        else
            say("scale is " .. db.scale .. ". Use /nk scale 0.6-1.6.")
        end
    elseif cmd == "perf" then
        -- Top addons by recent CPU time per frame (C_AddOnProfiler), else by memory (older clients).
        local names, A = {}, C_AddOns
        local count = (A and A.GetNumAddOns and A.GetNumAddOns()) or (GetNumAddOns and GetNumAddOns()) or 0
        for i = 1, count do
            local n = (A and A.GetAddOnInfo and A.GetAddOnInfo(i)) or (GetAddOnInfo and GetAddOnInfo(i))
            if n then names[#names + 1] = n end
        end
        local P, metric = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime
        local reader, unit
        if P and P.GetAddOnMetric and metric then
            reader, unit = function(n) return P.GetAddOnMetric(n, metric) end, "ms/frame"
        elseif GetAddOnMemoryUsage then
            if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
            reader, unit = function(n) return GetAddOnMemoryUsage(n) / 1024 end, "MB memory (no CPU profiler on this client)"
        end
        local top = L.topAddons(names, reader, 10)
        if #top == 0 then say("perf: no profiler data on this client.") return end
        say("perf: top addons by " .. unit .. ":")
        for i, t in ipairs(top) do say(string.format("%d. %s %.3f", i, t.name, t.value)) end
    else
        say(HELP)
    end
end
