-- AddonPresets: save which addons are on as a named preset, load it back later.  /presets
local ADDON, A = ...
local AO = C_AddOns
-- Saved data arrives after this file runs; ADDON_LOADED swaps in the real saved table.
local db = { sets = {} }
local window, reloadBtn
local rows = {}

local function say(msg) print("|cff33ccffAddonPresets:|r " .. msg) end

-- Forever keys a character's own addon switches by its GUID (as ConsolePort does); fall back to the name.
local function me() return (UnitGUID and UnitGUID("player")) or UnitName("player") end

-- Switches an addon for all characters and for this one, so a per-character "off" cannot keep it off.
local function setOn(name, on)
    local fn = on and AO.EnableAddOn or AO.DisableAddOn
    pcall(fn, name)
    pcall(fn, name, me())
end

-- Every installed addon as {name, enabled} for this character.
local function installed()
    local who, out = me(), {}
    for i = 1, AO.GetNumAddOns() do
        local name = AO.GetAddOnInfo(i)
        if type(name) == "table" then name = name.name end
        if name then
            local ok, st = pcall(AO.GetAddOnEnableState, i, who)
            local on
            if ok and type(st) == "number" then on = st > 0 else on = AO.IsAddOnLoaded(name) and true or false end
            out[#out + 1] = { name = name, enabled = on }
        end
    end
    return out
end

-- A preset by name, ignoring case.
local function findSet(name)
    name = A.cleanName(name)
    if not name then return nil end
    if db.sets[name] then return name end
    for n in pairs(db.sets) do if n:lower() == name:lower() then return n end end
end

-- WoW only reloads from a click or a typed command; the button stays up in case the automatic reload is refused.
local function reload()
    if not reloadBtn then
        reloadBtn = CreateFrame("Button", "AddonPresetsReload", UIParent, "UIPanelButtonTemplate")
        reloadBtn:SetSize(220, 32)
        reloadBtn:SetPoint("TOP", UIParent, "TOP", 0, -140)
        reloadBtn:SetFrameStrata("DIALOG")
        reloadBtn:SetText("AddonPresets: Reload UI now")
        reloadBtn:SetScript("OnClick", function() ReloadUI() end)
    end
    reloadBtn:Show()
    ReloadUI()
end

local refresh

local function save(name)
    name = A.cleanName(name)
    if not name then say("Give the preset a name.") return end
    if name == A.UNDO then say("That name is kept for undo; pick another.") return end
    name = findSet(name) or name
    db.sets[name] = A.capture(installed())
    local on, total = A.count(db.sets[name])
    say("Saved '" .. name .. "': " .. on .. " of " .. total .. " addons on.")
    if refresh then refresh() end
end

local function loadSet(name)
    local key = findSet(name)
    if not key then say("No preset called '" .. tostring(name) .. "'. Type /presets list.") return end
    local list = installed()
    local e = A.entries(db.sets[key], list)
    if key ~= A.UNDO then db.sets[A.UNDO] = A.capture(list) end
    for _, n in ipairs(e.on) do setOn(n, true) end
    for _, n in ipairs(e.off) do setOn(n, false) end
    local msg = "Loading '" .. key .. "': " .. #e.on .. " on, " .. #e.off .. " off."
    if e.missing > 0 then msg = msg .. " " .. e.missing .. " in the preset are no longer installed." end
    say(msg .. " Reloading; if it does not, click the Reload button or type /reload.")
    reload()
end

local function delete(name)
    local key = findSet(name)
    if not key then say("No preset called '" .. tostring(name) .. "'.") return end
    db.sets[key] = nil
    say("Deleted '" .. key .. "'.")
    if refresh then refresh() end
end

local function btn(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function row(i)
    if rows[i] then return rows[i] end
    local y = -76 - (i - 1) * 26
    local r = {}
    r.label = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("TOPLEFT", 16, y - 4)
    r.label:SetWidth(170)
    r.label:SetJustifyH("LEFT")
    r.load = btn(window, "Load", 60, function(self) loadSet(self.preset) end)
    r.load:SetPoint("TOPLEFT", 192, y)
    r.del = btn(window, "Delete", 60, function(self)
        if self.armed then delete(self.preset) return end
        self.armed = true
        self:SetText("Sure?")
    end)
    r.del:SetPoint("TOPLEFT", 256, y)
    rows[i] = r
    return r
end

function refresh()
    if not window then return end
    local names = A.sortedNames(db.sets)
    for i, name in ipairs(names) do
        local r = row(i)
        local on, total = A.count(db.sets[name])
        r.label:SetText(name .. "  |cff999999(" .. on .. "/" .. total .. " on)|r")
        r.load.preset, r.del.preset, r.del.armed = name, name, nil
        r.del:SetText("Delete")
        r.label:Show(); r.load:Show(); r.del:Show()
    end
    for i = #names + 1, #rows do rows[i].label:Hide(); rows[i].load:Hide(); rows[i].del:Hide() end
    window.empty:SetText(#names == 0 and "No presets yet. Type a name and click Save current." or "")
    window:SetHeight(math.max(120, 90 + #names * 26))
end

local function buildWindow()
    window = CreateFrame("Frame", "AddonPresetsFrame", UIParent, "BackdropTemplate")
    window:SetSize(330, 120)
    window:SetPoint("CENTER", 0, 80)
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    if window.SetBackdrop then
        window:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        window:SetBackdropColor(0, 0, 0, 0.85)
    end
    tinsert(UISpecialFrames, "AddonPresetsFrame") -- Escape closes it
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Addon Presets")
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    window.name = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    window.name:SetSize(160, 20)
    window.name:SetPoint("TOPLEFT", 20, -42)
    window.name:SetAutoFocus(false)
    window.name:SetMaxLetters(40)
    local function saveTyped()
        save(window.name:GetText())
        window.name:SetText("")
        window.name:ClearFocus()
    end
    window.name:SetScript("OnEnterPressed", saveTyped)
    window.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local saveBtn = btn(window, "Save current", 110, saveTyped)
    saveBtn:SetPoint("TOPLEFT", 192, -41)
    window.empty = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    window.empty:SetPoint("TOPLEFT", 16, -80)
end

local function toggle()
    if not window then buildWindow() end
    if window:IsShown() then window:Hide() else window:Show(); refresh() end
end

SLASH_ADDONPRESETS1 = "/presets"
SLASH_ADDONPRESETS2 = "/ap"
SlashCmdList["ADDONPRESETS"] = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "save" then save(rest)
    elseif cmd == "load" then loadSet(rest)
    elseif cmd == "delete" then delete(rest)
    elseif cmd == "undo" then loadSet(A.UNDO)
    elseif cmd == "list" then
        local names = A.sortedNames(db.sets)
        if #names == 0 then say("No presets yet.") end
        for _, n in ipairs(names) do local on, total = A.count(db.sets[n]); say(n .. " (" .. on .. "/" .. total .. " on)") end
    elseif cmd == "" then toggle()
    else say("/presets opens the window. Also: save NAME, load NAME, delete NAME, undo, list.") end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        AddonPresetsDB = AddonPresetsDB or {}
        AddonPresetsDB.sets = AddonPresetsDB.sets or {}
        -- A second copy per character. Once the account copy came back empty after a reload; if that happens,
        -- the presets are taken from this copy instead of being lost.
        AddonPresetsCharDB = AddonPresetsCharDB or {}
        local mirror = AddonPresetsCharDB.sets
        if next(AddonPresetsDB.sets) == nil and type(mirror) == "table" and next(mirror) ~= nil then
            for n, set in pairs(mirror) do AddonPresetsDB.sets[n] = set end
            say("Your presets were missing from the account save; restored them from this character's copy.")
        end
        AddonPresetsCharDB.sets = AddonPresetsDB.sets
        db = AddonPresetsDB
    end
end)
