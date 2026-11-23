-- Reaper: a quiet Shadow Word: Death signal. Game side: events, plates, target frame, action button, /reaper.
-- Every client call and every call into another addon is wrapped in pcall. UnitHealth / UnitHealthMax can be SECRET:
-- they are passed to widgets (Widgets.lua) and never compared or used in arithmetic here.
-- Event-driven: nothing runs while idle. Events mark the picture dirty and show a driver frame whose OnUpdate draws
-- once (throttled) and hides itself again. In combat a slow heartbeat (range, cooldown, damage-rate decay) keeps it on.
local ADDON, R = ...
local L, W = R.Logic, R.Widgets

local M = { widgets = {}, flags = { icon = true, flash = true, tick = true }, errors = 0, estimate = {}, plates = {},
    buttons = {}, glows = {} }
R.Main = M

local MAX_PLATES = 40
local THROTTLE = 0.1        -- at most this often while something changes
local HEARTBEAT = 0.5       -- in combat only: range, cooldown end, damage-rate decay
local ESTIMATE_RETRY, ESTIMATE_TRIES = 5, 12
local MAX_GLOWS = 3
local BUTTON_PREFIXES = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local EAB_SLOTS = 180       -- EllesmereUI names its buttons EABButton<slot>

local rate = L.newRate()
local reported = {}
local testing = false
local dirty, buttonsDirty = true, true
local sinceDraw, estimateTries = 0, 0
local opts = { icon = true, tick = true, size = 17 }
local targetPlateDrawn = false

-- Helpers -----------------------------------------------------------------------------------------------------
local function say(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Reaper|r " .. tostring(msg))
    end
end
M.say = say

local function noteError(err)
    M.errors = M.errors + 1
    err = tostring(err)
    if not reported[err] then
        reported[err] = true
        say("error (once): " .. err)
    end
end

local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then noteError(err) end
    return ok
end

-- pcall for client calls: returns the first two results, nil on error.
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

local function plain(v)
    if L.isSecret(v) then return nil end
    return v
end

local function now()
    return call(GetTime) or 0
end

local function inCombat()
    return plain(call(UnitAffectingCombat, "player")) and true or false
end

local function isTokenOk(unit)
    return type(unit) == "string" and not L.isSecret(unit)
end

local function plateToken(unit)
    return isTokenOk(unit) and unit:match("^nameplate%d+$") and true or false
end

local function mobKey(unit)
    local guid = call(UnitGUID, unit)
    if type(guid) == "string" and not L.isSecret(guid) then return guid end
    if plateToken(unit) then return "plate:" .. unit end
    if unit == "target" then return "target" end
    return nil
end

local function isTarget(unit)
    if unit == "target" then return true end
    return plain(call(UnitIsUnit, unit, "target")) and true or false
end

local function attackable(unit)
    if not plain(call(UnitExists, unit)) then return false end
    if not plain(call(UnitCanAttack, "player", unit)) then return false end
    if plain(call(UnitIsDead, unit)) then return false end
    return true
end

-- Driver: shown only while there is something to draw ----------------------------------------------------------------
local driver = CreateFrame("Frame")
M.driver = driver
driver:Hide()

local function wake()
    dirty = true
    driver:Show()
end
M.wake = wake

-- Setup: class, spell, description estimate -----------------------------------------------------------------------
local function spellKnown(id)
    local fns = { IsPlayerSpell, IsSpellKnown, C_SpellBook and C_SpellBook.IsSpellKnown }
    for _, fn in ipairs(fns) do
        if type(fn) == "function" then
            local ok, known = pcall(fn, id)
            if ok and known and not L.isSecret(known) then return true end
        end
    end
    return false
end

-- Description estimate of every rank, read out of combat (the text can be secret or empty in combat).
local function refreshEstimates()
    if not M.entry or inCombat() then return end
    for _, id in ipairs(M.entry.ids) do
        local desc
        if C_Spell and C_Spell.GetSpellDescription then
            desc = call(C_Spell.GetSpellDescription, id)
        end
        local value = L.parseDescription(desc)
        if value then
            M.estimate[id] = value
        elseif C_Spell and C_Spell.RequestLoadSpellData then
            -- empty description: the client has not loaded this rank's data yet (SPELL_DATA_LOAD_RESULT follows)
            call(C_Spell.RequestLoadSpellData, id)
        end
    end
end

local function spellTexture(id)
    local tex = C_Spell and C_Spell.GetSpellTexture and plain(call(C_Spell.GetSpellTexture, id))
    if type(tex) == "number" or type(tex) == "string" then return tex end
    return W.FALLBACK_ICON
end

local function pickSpell()
    M.spellId, M.wantEstimate = L.pickSpell(M.entry, spellKnown, M.db, M.estimate)
    M.texture = M.spellId and spellTexture(M.spellId) or W.FALLBACK_ICON
end

local scheduleRetry
local function refreshSpell()
    refreshEstimates()
    pickSpell()
    buttonsDirty = true
    wake()
    if M.wantEstimate or (M.spellId and not M.estimate[M.spellId]) then scheduleRetry() end
end

-- A few slow retries while a known rank still has no description (a timer, not an OnUpdate).
local retryPending = false
function scheduleRetry()
    if retryPending or estimateTries >= ESTIMATE_TRIES or not (C_Timer and C_Timer.After) then return end
    retryPending = true
    estimateTries = estimateTries + 1
    call(C_Timer.After, ESTIMATE_RETRY, function()
        retryPending = false
        safe(refreshSpell)
    end)
end

local function setupClass()
    local okClass, _, classFile = pcall(UnitClass, "player")
    if not okClass or L.isSecret(classFile) then classFile = nil end
    M.entry = L.classEntry(classFile)
    if not M.entry then return end
    M.learner = L.newLearner(M.db, M.entry, function(id) return M.estimate[id] end)
    refreshSpell()
end

-- Usable gate: known, mana, cooldown (per refresh) and range (per unit) ---------------------------------------------
local usableInfo = {}
local function globalUsable()
    local id = M.spellId
    if not id then return false end
    wipe(usableInfo)
    if C_Spell and C_Spell.IsSpellUsable then usableInfo.usable = call(C_Spell.IsSpellUsable, id) end
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = call(C_Spell.GetSpellCooldown, id)
        if type(cd) == "table" then
            usableInfo.cdStart, usableInfo.cdDuration, usableInfo.onGCD = cd.startTime, cd.duration, cd.isOnGCD
        end
    end
    usableInfo.now = now()
    return L.usable(usableInfo)
end

local rangeInfo = {}
local function inRange(unit)
    if not (C_Spell and C_Spell.IsSpellInRange) then return true end
    rangeInfo.inRange = call(C_Spell.IsSpellInRange, M.spellId, unit)
    return L.usable(rangeInfo)
end

-- Bars -----------------------------------------------------------------------------------------------------------
local function widgetsFor(host, bar, matchStrata)
    local w = M.widgets[host]
    if not w then
        w = W.new(host, bar, matchStrata)
        M.widgets[host] = w
    elseif w.bar ~= bar then
        W.attach(w, bar, matchStrata)
    end
    return w
end

local function barShown(bar)
    local ok, visible = pcall(bar.IsVisible, bar)
    if ok and not L.isSecret(visible) and visible == false then return false end
    return true
end

-- The health bar a plate shows, the frame our widgets hang on, and whether the bar belongs to a plate addon.
local function findPlateBar(plate, unit)
    local eui = EllesmereNameplates_NS
    local euiPlate = type(eui) == "table" and type(eui.plates) == "table" and eui.plates[unit]
    if type(euiPlate) == "table" and euiPlate.nameplate == plate and euiPlate.health then
        return euiPlate.health, euiPlate, true
    end
    local uf = plate.UnitFrame
    if type(uf) == "table" then
        local container = uf.HealthBarsContainer
        local bar = uf.healthBar or (type(container) == "table" and container.healthBar) or uf.HealthBar
        if type(bar) == "table" and barShown(bar) then return bar, plate, false end
    end
    return nil
end

-- Plate cache: M.plates[unit] = { plate, bar, host, strata } for plates that are up (NAME_PLATE_UNIT_ADDED/REMOVED).
-- An entry without a shown bar is looked up again on the next draw (a plate addon may build its bar after the event).
local function plateEntry(unit)
    local e = M.plates[unit]
    if not e then return nil end
    if not e.bar or not barShown(e.bar) then
        if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if not ok or not plate then return nil end
        if plate.IsForbidden and plate:IsForbidden() then return nil end
        e.plate = plate
        e.bar, e.host, e.strata = findPlateBar(plate, unit)
    end
    return e.bar and e or nil
end

local TARGET_BARS = { "EllesmereUIUnitFrames_Target.Health", "TargetFrameHealthBar", "TargetFrame.healthbar",
    "TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar" }

local function resolvePath(path)
    local obj = _G
    for part in path:gmatch("[^.]+") do
        if type(obj) ~= "table" then return nil end
        obj = obj[part]
    end
    return type(obj) == "table" and obj or nil
end

local function findTargetBar()
    for _, path in ipairs(TARGET_BARS) do
        local ok, bar = pcall(resolvePath, path)
        if ok and bar and bar.GetObjectType and barShown(bar) then return bar end
    end
    return nil
end

-- Action buttons that hold SW:D (scanned out of combat when the bars change; the buttons are only read) ------------
local function slotHasSpell(slot, slotSet)
    if slotSet[slot] then return true end
    if type(GetActionInfo) ~= "function" then return false end
    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok or L.isSecret(kind) or L.isSecret(id) then return false end
    return kind == "spell" and L.rankOfSpell(M.entry, id) ~= nil
end

local function buttonSlot(button)
    local slot = plain(rawget(button, "action"))
    if type(slot) ~= "number" and button.GetAttribute then
        local ok, a = pcall(button.GetAttribute, button, "action")
        slot = ok and plain(a) or nil
    end
    slot = tonumber(slot)
    return (slot and slot > 0) and slot or nil
end

local function scanButtons()
    wipe(M.buttons)
    if not M.entry then return end
    local slotSet = {}
    if C_ActionBar and C_ActionBar.FindSpellActionButtons then
        for _, id in ipairs(M.entry.ids) do
            local slots = call(C_ActionBar.FindSpellActionButtons, id)
            if type(slots) == "table" and not L.isSecret(slots) then
                for _, s in ipairs(slots) do if type(s) == "number" then slotSet[s] = true end end
            end
        end
    end
    local function consider(button)
        if type(button) ~= "table" or #M.buttons >= MAX_GLOWS then return end
        local slot = buttonSlot(button)
        if slot and slotHasSpell(slot, slotSet) then M.buttons[#M.buttons + 1] = button end
    end
    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for i = 1, 12 do consider(rawget(_G, prefix .. i)) end
    end
    for slot = 1, EAB_SLOTS do consider(rawget(_G, "EABButton" .. slot)) end
    for i, button in ipairs(M.buttons) do
        M.glows[i] = M.glows[i] or W.newGlow()
        W.placeGlow(M.glows[i], button)
    end
    for i = #M.buttons + 1, #M.glows do W.hideGlow(M.glows[i]) end
end
M.scanButtons = scanButtons

local function hideGlows()
    for _, g in ipairs(M.glows) do W.hideGlow(g) end
end

local function updateGlows(ready, health, finish)
    if not M.flags.flash or not M.db.buttonFlash or ready == nil then return hideGlows() end
    for i, g in ipairs(M.glows) do
        local button = M.buttons[i]
        if button and barShown(button) then
            local ok, err = W.showGlow(g, health, ready, finish)
            if not ok then noteError(err) end
        else
            W.hideGlow(g)
        end
    end
end

-- Drawing ------------------------------------------------------------------------------------------------------------
local function amountsFor(unit, maxHealth)
    if testing and isTarget(unit) then
        return maxHealth, maxHealth, 0 -- test: the icon shows (and pulses) on your target at any health
    end
    if not M.spellId then return nil, nil, nil end
    local swd = L.expectedSwd(M.db, M.spellId, M.estimate[M.spellId])
    local key = mobKey(unit)
    local perSecond = key and rate:rate(key, now()) or 0
    return L.amounts(swd, L.dotsOf(rawget(_G, "DoesItDie"), unit), now(), perSecond, M.db.leadTime)
end

local seen = {}

local function drawUnit(unit, host, bar, matchStrata, usable)
    local maxHealth, health = call(UnitHealthMax, unit), call(UnitHealth, unit)
    if maxHealth == nil or health == nil then return end
    local kill, ready, finish = amountsFor(unit, maxHealth)
    if kill == nil then return end
    local test = testing and isTarget(unit)
    if not test and not (usable and inRange(unit)) then return end
    local w = widgetsFor(host, bar, matchStrata)
    -- The icon sits on the target's plate only (on the target frame when its plate is not drawn); the tick on all.
    local wantsIcon = M.flags.icon and M.db.plateIcon
    if wantsIcon then
        if unit == "target" then wantsIcon = not targetPlateDrawn else wantsIcon = isTarget(unit) end
    end
    opts.icon = wantsIcon and true or false
    opts.tick = (M.flags.tick and M.db.tick and not test) and true or false
    opts.size, opts.texture = M.db.iconSize, M.texture
    local ok, err = W.draw(w, maxHealth, health, kill, ready, finish, opts)
    if not ok then return noteError(err) end
    seen[host] = true
    if opts.icon and unit ~= "target" then targetPlateDrawn = true end
    return kill, ready, health, finish
end

local function hideUnseen()
    for host, w in pairs(M.widgets) do
        if not seen[host] then W.hide(w) end
    end
end

local function refresh()
    wipe(seen)
    targetPlateDrawn = false
    if not M.entry and not testing then
        hideUnseen()
        return hideGlows()
    end
    if buttonsDirty and not inCombat() then
        buttonsDirty = false
        scanButtons()
    end
    local usable = globalUsable()
    for unit in pairs(M.plates) do
        if attackable(unit) then
            local e = plateEntry(unit)
            if e then drawUnit(unit, e.host, e.bar, e.strata, usable) end
        end
    end
    local ready, health, finish
    if attackable("target") then
        local bar = findTargetBar()
        local _
        if bar then _, ready, health, finish = drawUnit("target", bar, bar, false, usable) end
        if ready == nil and (testing or (usable and inRange("target"))) then
            -- no target frame drawn: the numbers still feed the button glow
            local mh, hp = call(UnitHealthMax, "target"), call(UnitHealth, "target")
            if mh ~= nil and hp ~= nil then _, ready, finish = amountsFor("target", mh); health = hp end
        end
    end
    hideUnseen()
    updateGlows(ready, health, finish)
end
M.refresh = refresh

driver:SetScript("OnUpdate", function(self, elapsed)
    sinceDraw = sinceDraw + (tonumber(elapsed) or 0)
    if sinceDraw < THROTTLE then return end
    local combat = inCombat()
    if not dirty and not (combat and sinceDraw >= HEARTBEAT) then
        if not combat then self:Hide() end
        return
    end
    sinceDraw = 0
    dirty = false
    if M.db then safe(refresh) end
    if not combat and not dirty then self:Hide() end
end)

-- Test mode: the icon on your target out of combat --------------------------------------------------------------------
function M.testOn() return testing end

function M.setTest(on)
    if not on then
        testing = false
        wake()
        return true
    end
    if inCombat() then
        say("test mode needs you out of combat.")
        return false
    end
    if not plain(call(UnitExists, "target")) then
        say("test mode: target something first.")
        return false
    end
    testing = true
    wake()
    return true
end

-- Options shared by the slash command and the options window.
function M.setOption(key, value)
    if key == "iconSize" then
        local size = L.clampIcon(tonumber(value))
        if not size then return false end
        M.db.iconSize = size
    elseif key == "plateIcon" or key == "buttonFlash" or key == "tick" then
        M.db[key] = value and true or false
    else
        return false
    end
    wake()
    return M.db[key]
end

function M.status()
    local parts = {}
    if not M.entry then
        parts[#parts + 1] = "inactive (no execute spell for this class)"
    else
        local id = M.spellId
        parts[#parts + 1] = M.entry.spell .. (id and (" rank " .. tostring(L.rankOfSpell(M.entry, id))) or " (not found in spellbook)")
        if id then
            local avg, n = L.learnedAvg(M.db, id), L.learnedN(M.db, id)
            if avg then
                parts[#parts + 1] = string.format("learned %.0f from %d hits", avg, n)
            elseif M.estimate[id] then
                parts[#parts + 1] = string.format("estimate %.0f (no hits learned yet)", M.estimate[id])
            else
                parts[#parts + 1] = "no amount known yet"
            end
        end
    end
    parts[#parts + 1] = "icon " .. (M.db.plateIcon and "on" or "off") .. " " .. M.db.iconSize .. " px"
    parts[#parts + 1] = "button flash " .. (M.db.buttonFlash and (#M.buttons .. " button(s) found") or "off")
    parts[#parts + 1] = "lead " .. string.format("%.1f", M.db.leadTime) .. " s"
    parts[#parts + 1] = rawget(_G, "DoesItDie") and "DoesItDie found" or "DoesItDie not found"
    return table.concat(parts, "; ")
end

-- NectarKit modules ---------------------------------------------------------------------------------------------------------
local MODULES = {
    { key = "icon", label = "SW:D icon on the target's plate" },
    { key = "flash", label = "Soft glow on the SW:D action button" },
    { key = "tick", label = "Thin kill tick on plates" },
}

local function registerModules()
    for _, m in ipairs(MODULES) do
        local key = m.key
        local function onToggle(on)
            M.flags[key] = on and true or false
            wake()
        end
        if type(NectarKit_RegisterModule) == "function" then
            local ok, state = pcall(NectarKit_RegisterModule, "Reaper", key, m.label, true, onToggle)
            if ok and type(state) == "boolean" then M.flags[key] = state end
        else
            -- NectarKit loads later (or is absent): leave a record for it to drain.
            NectarKit_Queue = NectarKit_Queue or {}
            table.insert(NectarKit_Queue, { addon = "Reaper", key = key, label = m.label, default = true, onToggle = onToggle })
        end
    end
end
registerModules()

-- Events ----------------------------------------------------------------------------------------------------------------------
local function watched(unit)
    return unit == "target" or (plateToken(unit) and M.plates[unit] ~= nil)
end

local function onCombat(unit, action, flag, amount, school)
    if not isTokenOk(unit) then return end
    if not (unit == "target" or unit == "focus" or plateToken(unit)) then return end
    if L.isSecret(action) or action ~= "WOUND" then return end
    local t = now()
    if M.learner then M.learner:onCombat(isTarget(unit), action, flag, amount, school, t) end
    if attackable(unit) then
        local key = mobKey(unit)
        if key then rate:add(key, t, amount, unit) end
    end
    if M.entry and watched(unit) then wake() end
end

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON then return end
    ReaperDB = L.sanitize(ReaperDB)
    M.db = ReaperDB
end

function handlers.PLAYER_LOGIN()
    if not M.db then M.db = L.sanitize(ReaperDB); ReaperDB = M.db end
    setupClass()
end

function handlers.PLAYER_ENTERING_WORLD()
    -- plates that were up before we listened
    wipe(M.plates)
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        for i = 1, MAX_PLATES do
            local unit = "nameplate" .. i
            if call(C_NamePlate.GetNamePlateForUnit, unit) then M.plates[unit] = {} end
        end
    end
    if M.entry then refreshSpell() end
end

function handlers.SPELLS_CHANGED()
    if M.entry then refreshSpell() end
end

function handlers.SPELL_DATA_LOAD_RESULT(spellId)
    if M.entry and L.rankOfSpell(M.entry, spellId) then refreshSpell() end
end

function handlers.PLAYER_REGEN_ENABLED()
    if M.entry then refreshSpell() end -- also rescans the buttons a combat change left pending
end

function handlers.PLAYER_REGEN_DISABLED()
    testing = false
    wake()
end

function handlers.PLAYER_TARGET_CHANGED() wake() end

function handlers.NAME_PLATE_UNIT_ADDED(unit)
    if not plateToken(unit) then return end
    -- A plate token goes to the next mob that gets a plate: damage keyed by it belonged to the one before.
    rate:forget("plate:" .. unit)
    M.plates[unit] = {}
    wake()
end

function handlers.NAME_PLATE_UNIT_REMOVED(unit)
    if not plateToken(unit) then return end
    rate:forget("plate:" .. unit)
    M.plates[unit] = nil
    wake()
end

local function onHealth(unit)
    if M.entry and isTokenOk(unit) and watched(unit) then wake() end
end
handlers.UNIT_HEALTH = onHealth
handlers.UNIT_MAXHEALTH = onHealth

local function onSpellState()
    if M.entry then wake() end
end
handlers.SPELL_UPDATE_USABLE = onSpellState
handlers.SPELL_UPDATE_COOLDOWN = onSpellState

local function onBars()
    if not M.entry then return end
    buttonsDirty = true
    wake()
end
handlers.ACTIONBAR_SLOT_CHANGED = onBars
handlers.ACTIONBAR_PAGE_CHANGED = onBars
handlers.UPDATE_BONUS_ACTIONBAR = onBars

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellId)
    if unit ~= "player" or not M.learner then return end
    M.learner:onCast(spellId, now())
end

handlers.UNIT_COMBAT = onCombat

local frame = CreateFrame("Frame")
M.frame = frame
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...)
    local fn = handlers[event]
    if fn then safe(fn, ...) end
end)

-- Slash command --------------------------------------------------------------------------------------------------------------------
local function onOff(word)
    if word == "on" then return true elseif word == "off" then return false end
    return nil
end

local function refreshOptions()
    if R.Options and R.Options.refresh then R.Options.refresh() end
end

SLASH_REAPER1 = "/reaper"
SlashCmdList.REAPER = function(msg)
    local cmd = strlower and strlower(strtrim(msg or "")) or string.lower(strtrim(msg or ""))
    if cmd == "" then
        if R.Options then R.Options.toggle() end
    elseif cmd == "test" then
        local ok = M.setTest(not testing)
        if ok and testing then say("test mode on: the SW:D icon shows on your target. /reaper test again to stop.")
        elseif ok then say("test mode off.") end
        refreshOptions()
    elseif cmd == "status" then
        say(M.status())
    elseif cmd:match("^icon") then
        local arg = cmd:match("^icon%s+(%S+)$")
        local flag = onOff(arg)
        if flag ~= nil then
            M.setOption("plateIcon", flag); say("plate icon " .. arg)
        elseif arg and M.setOption("iconSize", arg) then
            say("icon size " .. M.db.iconSize .. " px")
        else
            say("/reaper icon on|off|<" .. L.ICON_MIN .. "-" .. L.ICON_MAX .. "> (now " .. (M.db.plateIcon and "on" or "off") .. ", " .. M.db.iconSize .. " px).")
        end
        refreshOptions()
    elseif cmd:match("^flash") or cmd:match("^tick") then
        local word, arg = cmd:match("^(%a+)%s*(%a*)$")
        local key = word == "flash" and "buttonFlash" or "tick"
        local flag = onOff(arg)
        if flag ~= nil then
            M.setOption(key, flag); say(word .. " " .. arg)
        else
            say("/reaper " .. tostring(word) .. " on|off (now " .. (M.db[key] and "on" or "off") .. ").")
        end
        refreshOptions()
    else
        say("/reaper opens the options. /reaper icon on|off|<size>. /reaper flash on|off. /reaper tick on|off. /reaper test shows the icon on your target. /reaper status shows what is learned.")
    end
end
