-- Options window: one checkbox per Entries.lua add-on (applies after a reload) and, indented under it,
-- one per registered module (applies at once). Built on first use. Main.lua provides NK.say, NK.darkGold,
-- NK.getDB and NK.modules before this runs.
local _, NK = ...
local L = NK.Logic

local WIDTH, ROW_H, HEADER, FOOTER, INDENT = 380, 22, 58, 48, 22
local GOLD = { 1, 0.82, 0 }
local win
local rows = {}

local function readStates()
    return L.readStates(L.pickAddOnApi(_G))
end

-- The enable state when the game started; anything different from it needs a reload.
function NK.captureBaseline()
    NK.baseline = readStates().enabled
end

local function reloadUI()
    local fn = ReloadUI or (C_UI and C_UI.Reload)
    if fn then
        local ok, err = pcall(fn)
        if not ok then NK.say("reload failed: " .. tostring(err)) end
    end
end

local function newCheck(parent)
    local ok, cb = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
    if not ok or not cb then cb = CreateFrame("CheckButton", nil, parent) end
    cb:SetSize(22, 22)
    return cb
end

local refresh

local function getRow(i)
    local r = rows[i]
    if r then return r end
    r = {}
    r.cb = newCheck(win)
    r.label = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT", r.cb, "RIGHT", 2, 1)
    r.note = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.note:SetPoint("RIGHT", win, "RIGHT", -14, 0)
    r.cb:SetScript("OnClick", function(self)
        local d = r.data
        if d then
            local want = self:GetChecked() and true or false
            if d.kind == "module" then
                NK.modules:set(d.addon, d.key, want)
            elseif not d.locked and d.installed then
                local ok, err = L.setAddonEnabled(L.pickAddOnApi(_G), d.addon, want)
                if not ok then NK.say(d.addon .. ": " .. tostring(err)) end
            end
        end
        refresh()
    end)
    rows[i] = r
    return r
end

local function setColor(fs, r, g, b)
    if fs.SetTextColor then fs:SetTextColor(r, g, b) end
end

refresh = function()
    if not win then return end
    local states = readStates()
    if not NK.baseline then NK.captureBaseline() end
    local list = L.buildOptionsList(NK.Entries, states, NK.baseline, NK.modules)
    for i, d in ipairs(list) do
        local r = getRow(i)
        r.data = d
        local indent = d.kind == "module" and INDENT or 0
        local y = -(HEADER + (i - 1) * ROW_H)
        r.cb:ClearAllPoints()
        r.cb:SetPoint("TOPLEFT", win, "TOPLEFT", 12 + indent, y)
        r.cb.nkAddon, r.cb.nkKey = d.addon, d.key
        if d.kind == "module" then
            r.cb:SetChecked(d.on)
            r.label:SetText(d.label)
            setColor(r.label, 0.85, 0.85, 0.85)
            r.note:SetText("")
            if r.cb.Enable then r.cb:Enable() end
        else
            r.cb:SetChecked(d.enabled)
            r.label:SetText(d.title)
            if not d.installed then
                setColor(r.label, 0.5, 0.5, 0.5)
                r.note:SetText("not installed")
                if r.cb.Disable then r.cb:Disable() end
            elseif d.locked then
                setColor(r.label, GOLD[1], GOLD[2], GOLD[3])
                r.note:SetText("always on")
                if r.cb.Disable then r.cb:Disable() end
            else
                if d.enabled then setColor(r.label, GOLD[1], GOLD[2], GOLD[3]) else setColor(r.label, 0.65, 0.65, 0.65) end
                r.note:SetText(d.pending and "reload needed" or "")
                if r.cb.Enable then r.cb:Enable() end
            end
        end
        r.cb:Show(); r.label:Show(); r.note:Show()
    end
    for i = #list + 1, #rows do
        local r = rows[i]
        r.data = nil
        r.cb.nkAddon, r.cb.nkKey = nil, nil
        r.cb:Hide(); r.label:Hide(); r.note:Hide()
    end
    win:SetSize(WIDTH, HEADER + #list * ROW_H + FOOTER)
    win.pending:SetText(L.pendingText(L.pendingCount(NK.baseline, states)))
end

function NK.RefreshOptions()
    if win and win:IsShown() then refresh() end
end

local function build()
    if win then return end
    win = CreateFrame("Frame", "NectarKitOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    NK.darkGold(win)

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("NectarKit settings")
    setColor(title, GOLD[1], GOLD[2], GOLD[3])
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 14, -34)
    hint:SetText("Addon switches apply after a reload. Module switches apply at once.")

    local ok, close = pcall(CreateFrame, "Button", nil, win, "UIPanelCloseButton")
    if ok and close then
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() win:Hide() end)
    end

    win.pending = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.pending:SetPoint("BOTTOMLEFT", 14, 16)
    local ok2, btn = pcall(CreateFrame, "Button", nil, win, "UIPanelButtonTemplate")
    if not ok2 or not btn then btn = CreateFrame("Button", nil, win) end
    btn:SetSize(96, 22)
    btn:SetPoint("BOTTOMRIGHT", -14, 12)
    btn:SetText("Reload UI")
    btn:SetScript("OnClick", reloadUI)
    win.reload = btn

    table.insert(UISpecialFrames, "NectarKitOptions") -- Escape closes it
    win:Hide()
end

function NK.ToggleOptions()
    build()
    if win:IsShown() then
        win:Hide()
    else
        local db = NK.getDB and NK.getDB()
        if db then win:SetScale(db.scale) end
        refresh()
        win:Show()
    end
end
