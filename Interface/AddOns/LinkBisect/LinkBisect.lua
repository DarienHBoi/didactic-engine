-- LinkBisect: finds the addon that breaks clicking item links in chat.  /lb start, then /lb bad when a click does nothing.
local ADDON = ...
-- Saved state arrives after this file runs; ADDON_LOADED swaps in the real saved table.
local DB = {}
local AO = C_AddOns
local TEST = "|cff1eff00|Hitem:6948::::::::1:::::::|h[Hearthstone]|h|r"

-- Straight into the chat window: print() output does not show on this setup.
local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffLinkBisect:|r " .. msg) end

-- The verdict, after the reload that applies it: in chat and in big text mid-screen.
local function showResult()
    local msg = "Culprit: " .. tostring(DB.result) .. " (now off). Try clicking an item link. /lb restore turns everything back on."
    say(msg)
    if UIErrorsFrame then UIErrorsFrame:AddMessage("LinkBisect " .. msg, 1, 0.8, 0) end
end

-- WoW only reloads from a click or a typed command, so a button stays up in case the automatic reload is refused.
local reloadBtn
local function reload()
    if not reloadBtn then
        reloadBtn = CreateFrame("Button", "LinkBisectReload", UIParent, "UIPanelButtonTemplate")
        reloadBtn:SetSize(220, 32)
        reloadBtn:SetPoint("TOP", UIParent, "TOP", 0, -140)
        reloadBtn:SetFrameStrata("DIALOG")
        reloadBtn:SetText("LinkBisect: Reload UI now")
        reloadBtn:SetScript("OnClick", function() ReloadUI() end)
    end
    reloadBtn:Show()
    say("If the UI does not reload, click the Reload button at the top of the screen or type /reload.")
    ReloadUI()
end

local function nameOf(i)
    local r = AO.GetAddOnInfo(i)
    if type(r) == "table" then return r.name end
    return r
end

-- AddonPresets stays on through the hunt so its window keeps working (it is not the culprit: it came later).
local KEEP = { AddonPresets = true }
local BACKUP = "(before LinkBisect)"

local function loadedNow()
    local t = {}
    for i = 1, AO.GetNumAddOns() do
        local n = nameOf(i)
        if n and n ~= ADDON and not KEEP[n] and not n:find("^Blizzard_") and AO.IsAddOnLoaded(n) then t[#t + 1] = n end
    end
    return t
end

-- Forever keys a character's own addon switches by its GUID (as ConsolePort does); fall back to the name.
local function me() return (UnitGUID and UnitGUID("player")) or UnitName("player") end

-- Switches an addon for all characters and for this one, so a per-character "off" cannot keep it off.
local function setOn(n, on)
    local fn = on and AO.EnableAddOn or AO.DisableAddOn
    pcall(fn, n)
    pcall(fn, n, me())
end

local function setAll(list, on)
    for _, n in ipairs(list or {}) do setOn(n, on) end
end

-- Which addons are on right now (for this character), every addon except this one and Blizzard's.
local function snapshot()
    local who, set = me(), {}
    for i = 1, AO.GetNumAddOns() do
        local n = nameOf(i)
        if n and n ~= ADDON and not n:find("^Blizzard_") then
            local ok, st = pcall(AO.GetAddOnEnableState, i, who)
            if ok and type(st) == "number" then set[n] = st > 0 else set[n] = AO.IsAddOnLoaded(n) and true or false end
        end
    end
    return set
end

-- Keeps the starting setup here and, when AddonPresets is installed, as a preset you can load from /presets.
local function backup()
    DB.backup = snapshot()
    if type(AddonPresetsDB) == "table" then
        AddonPresetsDB.sets = AddonPresetsDB.sets or {}
        local copy = {}
        for n, on in pairs(DB.backup) do copy[n] = on end
        AddonPresetsDB.sets[BACKUP] = copy
        say("Your setup is saved as the preset '" .. BACKUP .. "' (see /presets). /lb restore puts it back.")
    else
        say("Your setup is saved. /lb restore puts it back.")
    end
end

-- Back to the starting setup (runs started before backups existed just turn everything back on).
local function putBack()
    if not DB.backup then return setAll(DB.all, true) end
    for n, on in pairs(DB.backup) do setOn(n, on) end
end

-- Puts the backup back into /presets if the preset went missing.
local function seedPreset()
    if DB.backup and type(AddonPresetsDB) == "table" and type(AddonPresetsDB.sets) == "table" and not AddonPresetsDB.sets[BACKUP] then
        local copy = {}
        for n, on in pairs(DB.backup) do copy[n] = on end
        AddonPresetsDB.sets[BACKUP] = copy
    end
end

local function split(list)
    local h, a, b = math.floor(#list / 2), {}, {}
    for i, n in ipairs(list) do if i <= h then a[#a + 1] = n else b[#b + 1] = n end end
    return a, b
end

local function finish()
    local culprit = DB.suspects[1]
    putBack()
    if culprit then setOn(culprit, false) end
    DB.active, DB.waiting = nil, nil
    DB.result, DB.shown = culprit, nil
    say("Culprit: " .. tostring(culprit) .. ". Everything else is enabled again and the culprit is disabled. Reloading. Re-enable it later with /lb restore.")
    reload()
end

local function step()
    if #DB.suspects <= 1 then return finish() end
    local off, on = split(DB.suspects)
    DB.off, DB.on = off, on
    setAll(off, false)
    setAll(on, true)
    DB.waiting = true
    say("Round " .. (DB.round or 1) .. ": turning off " .. #off .. " of " .. #DB.suspects .. " suspects. Reloading.")
    DB.round = (DB.round or 1) + 1
    reload()
end

local function verdict(works)
    if not DB.active or not DB.waiting then return end
    DB.waiting = false
    if works then
        setAll(DB.on, true)
        DB.suspects = DB.off
        say("Click works: the culprit is among the " .. #DB.suspects .. " addons that were off.")
    else
        setAll(DB.off, true)
        DB.suspects = DB.on
        say("Click broken: the culprit is among the " .. #DB.suspects .. " addons that were on.")
    end
    step()
end

local function restore()
    putBack()
    DB.active, DB.waiting, DB.suspects = nil, nil, nil
    say("Your setup from before the hunt is back. Reloading.")
    reload()
end

local function promptTest()
    say("Click this link in chat (it checks itself). If nothing happens, type /lb bad:")
    DEFAULT_CHAT_FRAME:AddMessage(TEST)
end

hooksecurefunc("SetItemRef", function(link)
    if DB.active and DB.waiting and type(link) == "string" and link:find("^item:6948") then
        verdict(true)
    end
end)

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then
            LinkBisectDB = LinkBisectDB or {}
            DB = LinkBisectDB
        end
        return
    end
    seedPreset()
    if DB.active and DB.waiting then C_Timer.After(3, promptTest) end
    if DB.result and not DB.shown then
        DB.shown = true
        C_Timer.After(3, showResult)
    end
end)


-- ===== Diagnostics: who catches the click? =====
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local function frameName(fr)
    local ok, n = pcall(function() return fr.GetDebugName and fr:GetDebugName() or fr:GetName() end)
    if ok and n then return n end
    return tostring(fr)
end

local function mouseOn(fr)
    if fr.IsMouseClickEnabled then return fr:IsMouseClickEnabled() end
    return fr.IsMouseEnabled and fr:IsMouseEnabled()
end

-- Lists visible, mouse-enabled frames under the cursor, topmost first.
local function scanOver()
    local hits = {}
    local fr = EnumerateFrames()
    while fr do
        local ok, hit = pcall(function()
            return fr:IsVisible() and fr:IsMouseOver() and mouseOn(fr)
        end)
        if ok and hit then
            hits[#hits + 1] = { fr = fr, s = STRATA[fr:GetFrameStrata()] or 0, l = fr:GetFrameLevel() or 0 }
        end
        fr = EnumerateFrames(fr)
    end
    table.sort(hits, function(a, b) if a.s ~= b.s then return a.s > b.s end return a.l > b.l end)
    say("Mouse-enabled frames under the cursor, topmost first (" .. #hits .. "):")
    for i = 1, math.min(#hits, 8) do
        local h = hits[i]
        local par = h.fr.GetParent and h.fr:GetParent()
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d. %s  [%s, level %d]  parent: %s", i, frameName(h.fr), h.fr:GetFrameStrata(), h.l, par and frameName(par) or "none"))
    end
    if #hits == 0 then say("Nothing mouse-enabled is under the cursor (is it over the chat link?).") end
end

local traced, tracing = false, false
local function log(msg) if tracing then DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00LB trace:|r " .. msg) end end

local function installTrace()
    if traced then return end
    traced = true
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then
            cf:HookScript("OnHyperlinkClick", function(_, link) log("ChatFrame" .. i .. " got click: " .. tostring(link)) end)
            cf:HookScript("OnHyperlinkEnter", function(_, link) log("ChatFrame" .. i .. " hover: " .. tostring(link)) end)
        end
    end
    hooksecurefunc("SetItemRef", function(link) log("SetItemRef called: " .. tostring(link)) end)
    if ItemRefTooltip then
        hooksecurefunc(ItemRefTooltip, "SetHyperlink", function(_, link) log("ItemRefTooltip:SetHyperlink " .. tostring(link)) end)
    end
end

local function chatState()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf and cf:IsVisible() then
            local en = cf.GetHyperlinksEnabled and tostring(cf:GetHyperlinksEnabled()) or "?"
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  ChatFrame%d: shown, hyperlinksEnabled=%s, mouse=%s, strata=%s, level=%d, alpha=%.2f",
                i, en, tostring(mouseOn(cf)), cf:GetFrameStrata(), cf:GetFrameLevel(), cf:GetEffectiveAlpha()))
        end
    end
end

local function diag()
    say("Chat windows:")
    chatState()
    scanOver()
end

SLASH_LINKBISECT1 = "/lb"
SlashCmdList["LINKBISECT"] = function(msg)
    local arg = (msg or ""):lower():match("^%s*%S+%s+(.*)$")
    msg = (msg or ""):lower():match("^%s*(%S*)")
    if msg == "start" then
        backup()
        DB.all = loadedNow()
        DB.suspects = {}
        for i, n in ipairs(DB.all) do DB.suspects[i] = n end
        DB.active, DB.round, DB.result = true, 1, nil
        say("Starting with " .. #DB.all .. " addons. Each round reloads the UI.")
        step()
    elseif msg == "over" then
        local secs = tonumber((arg or ""):match("%d+")) or 5
        say("Hover over a chat link now. Scanning in " .. secs .. " seconds.")
        C_Timer.After(secs, diag)
    elseif msg == "trace" then
        tracing = not tracing
        if tracing then installTrace() end
        say("Click trace " .. (tracing and "ON: click a chat link and read the yellow lines." or "off."))
    elseif msg == "bad" then
        verdict(false)
    elseif msg == "good" then
        verdict(true)
    elseif msg == "status" then
        if DB.active then say("Running: round " .. tostring(DB.round) .. ", " .. #(DB.suspects or {}) .. " suspects left.")
        elseif DB.result then showResult()
        else say("No hunt run yet. /lb start begins one.") end
    elseif msg == "restore" or msg == "stop" then
        if DB.all then restore() else say("Nothing to restore.") end
    else
        say("/lb over [secs]  who is under the mouse  |  /lb trace  log link clicks  |  /lb start  addon bisect  |  /lb bad  |  /lb status  |  /lb restore")
        if DB.active then say("Running: " .. #(DB.suspects or {}) .. " suspects left.") end
    end
end
