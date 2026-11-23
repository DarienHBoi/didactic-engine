-- Pure logic: no frames, no client calls except through functions handed in. Everything here is unit tested.
local _, NK = ...
local L = {}
NK.Logic = L

L.DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
L.MIN_SCALE, L.MAX_SCALE = 0.6, 1.6
L.DEFAULT_ANGLE = 215

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end

-- Client function lookup: Forever has the C_AddOns namespace; fall back to the old globals.
function L.pickMetadata(env)
    local c = env.C_AddOns
    return (c and c.GetAddOnMetadata) or env.GetAddOnMetadata
end

function L.pickIsLoaded(env)
    local c = env.C_AddOns
    return (c and c.IsAddOnLoaded) or env.IsAddOnLoaded
end

-- Entries whose addon is loaded and whose slash handler is really registered. Never throws.
function L.visibleEntries(entries, isLoaded, slashList)
    local out = {}
    if type(entries) ~= "table" or type(isLoaded) ~= "function" or type(slashList) ~= "table" then return out end
    for _, e in ipairs(entries) do
        if e.key and type(slashList[e.key]) == "function" then
            local ok, loaded = pcall(isLoaded, e.addon)
            if ok and loaded then out[#out + 1] = e end
        end
    end
    return out
end

-- The addon's own .toc IconTexture first, then the data table icon, then a built-in default.
function L.resolveIcon(entry, getMetadata)
    if type(getMetadata) == "function" then
        local ok, tex = pcall(getMetadata, entry.addon, "IconTexture")
        if ok and type(tex) == "string" and tex ~= "" then return tex end
    end
    return entry.icon or L.DEFAULT_ICON
end

-- Call the addon's slash handler with an empty argument. Returns pcall's results.
function L.runEntry(entry, slashList)
    local fn = slashList and entry.key and slashList[entry.key]
    if type(fn) ~= "function" then return false, "no slash handler" end
    return pcall(fn, "")
end

-- Minimap angle maths (degrees, 0 = right, 90 = up).
function L.position(angleDeg, radius)
    local a = math.rad(angleDeg)
    return math.cos(a) * radius, math.sin(a) * radius
end

function L.angleFromCursor(cx, cy, mx, my)
    local deg = math.deg(atan2(my - cy, mx - cx))
    if deg < 0 then deg = deg + 360 end
    return deg
end

function L.normalizeAngle(a, fallback)
    if type(a) ~= "number" then return fallback or 0 end
    return a % 360
end

function L.clampScale(s)
    if type(s) ~= "number" then return 1 end
    if s < L.MIN_SCALE then return L.MIN_SCALE end
    if s > L.MAX_SCALE then return L.MAX_SCALE end
    return s
end

-- Icon grid. Entries 1..n get {x, y} offsets from the panel's TOPLEFT.
function L.layout(n, maxCols, cell, pad)
    local count = math.max(n, 1)
    local cols = math.min(count, maxCols)
    local rows = math.ceil(count / cols)
    local lay = { cols = cols, rows = rows, width = cols * cell + (cols + 1) * pad, height = rows * cell + (rows + 1) * pad }
    for i = 1, n do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        lay[i] = { x = pad + col * (cell + pad), y = -(pad + row * (cell + pad)) }
    end
    return lay
end

-- Which panel corner touches which button corner so the panel opens toward the screen centre.
function L.anchorFor(bx, by, sw, sh)
    local top, right = by > sh / 2, bx > sw / 2
    return (top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"),
        (top and "BOTTOM" or "TOP") .. (right and "LEFT" or "RIGHT")
end

-- Saved settings with defaults and sanity limits.
function L.initDB(db)
    if type(db) ~= "table" then db = {} end
    db.angle = L.normalizeAngle(db.angle, L.DEFAULT_ANGLE)
    if type(db.angle) ~= "number" or db.angle ~= db.angle then db.angle = L.DEFAULT_ANGLE end
    if type(db.hideButtons) ~= "boolean" then db.hideButtons = true end
    db.scale = L.clampScale(db.scale)
    if type(db.modules) ~= "table" then db.modules = {} end
    return db
end

-- "/nk buttons on" -> "buttons", "on"
function L.parseCommand(msg)
    local cmd, arg = tostring(msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    return cmd or "", arg or ""
end

function L.parseSwitch(arg, current)
    if arg == "on" or arg == "1" or arg == "true" or arg == "show" then return true end
    if arg == "off" or arg == "0" or arg == "false" or arg == "hide" then return false end
    return not current
end

-- Hide/restore bookkeeping for the other addons' minimap buttons.
-- apply(true) hides every button frame found (and keeps it hidden if its addon shows it again via an OnShow hook);
-- apply(false) puts back only the buttons that were meant to be visible. Returns found, missing counts.
-- Frames are only looked up by name; nothing in the other addons is edited.
function L.newHider(entries, getFrame)
    local H = { enabled = false, state = {} }

    local function hideNow(st)
        if st.frame then pcall(st.frame.Hide, st.frame) end
    end

    function H:apply(on)
        self.enabled = on and true or false
        local found, missing = 0, 0
        for _, e in ipairs(entries) do
            if e.button then
                local st = self.state[e.button]
                local frame = st and st.frame
                if not frame then
                    local ok, f = pcall(getFrame, e.button)
                    frame = ok and f or nil
                end
                if not frame then
                    missing = missing + 1
                else
                    found = found + 1
                    if not st then
                        st = { frame = frame, hooked = false, hidden = false, wantShown = false }
                        self.state[e.button] = st
                    end
                    if on then
                        if not st.hooked then
                            local ok = pcall(frame.HookScript, frame, "OnShow", function()
                                if H.enabled and st.hidden then
                                    st.wantShown = true
                                    hideNow(st)
                                end
                            end)
                            st.hooked = ok
                        end
                        if not st.hidden then
                            local ok, shown = pcall(frame.IsShown, frame)
                            st.wantShown = ok and shown and true or false
                            st.hidden = true
                            hideNow(st)
                        else
                            local ok, shown = pcall(frame.IsShown, frame)
                            if ok and shown then st.wantShown = true; hideNow(st) end
                        end
                    elseif st.hidden then
                        st.hidden = false
                        if st.wantShown then pcall(frame.Show, frame) end
                    end
                end
            end
        end
        return found, missing
    end

    return H
end

-- Options: add-on enable state ------------------------------------------------
-- Forever has the C_AddOns namespace; the old globals are the fallback. Every call goes through pcall.

L.SELF = "NectarKit"

function L.pickAddOnApi(env)
    local c = env.C_AddOns or {}
    return {
        getNum = c.GetNumAddOns or env.GetNumAddOns,
        getInfo = c.GetAddOnInfo or env.GetAddOnInfo,
        getState = c.GetAddOnEnableState or env.GetAddOnEnableState,
        enable = c.EnableAddOn or env.EnableAddOn,
        disable = c.DisableAddOn or env.DisableAddOn,
        -- C_AddOns.GetAddOnEnableState(name, character); the old global is (character, name)
        newStyle = c.GetAddOnEnableState ~= nil,
    }
end

-- Set of installed add-on folder names. GetAddOnInfo returns a table (new) or name, title, ... (old).
function L.scanInstalled(api)
    local set = {}
    if type(api.getNum) ~= "function" or type(api.getInfo) ~= "function" then return set end
    local ok, n = pcall(api.getNum)
    if not ok or type(n) ~= "number" then return set end
    for i = 1, n do
        local ok2, a = pcall(api.getInfo, i)
        if ok2 then
            if type(a) == "table" then a = a.name end
            if type(a) == "string" and a ~= "" then set[a] = true end
        end
    end
    return set
end

-- true / false, or nil when the client cannot tell. State 1 (on for some characters) counts as on.
function L.readEnableState(api, name)
    if type(api.getState) ~= "function" then return nil end
    local ok, r
    if api.newStyle then ok, r = pcall(api.getState, name) else ok, r = pcall(api.getState, nil, name) end
    if not ok then return nil end
    if type(r) == "number" then return r ~= 0 end
    if type(r) == "boolean" then return r end
    return nil
end

function L.readStates(api)
    local installed = L.scanInstalled(api)
    local enabled = {}
    for name in pairs(installed) do
        local e = L.readEnableState(api, name)
        if e ~= nil then enabled[name] = e end
    end
    return { installed = installed, enabled = enabled }
end

function L.canToggleAddon(name)
    return name ~= L.SELF
end

function L.setAddonEnabled(api, name, on)
    if not L.canToggleAddon(name) then return false, "cannot switch itself off" end
    local fn = on and api.enable or api.disable
    if type(fn) ~= "function" then return false, "no API" end
    local ok, err = pcall(fn, name)
    if not ok then return false, err end
    return true
end

-- Add-ons whose enable state now differs from the state captured at login (those need a reload).
function L.pendingCount(baseline, states)
    local n = 0
    if type(baseline) ~= "table" or type(states) ~= "table" then return 0 end
    for name, was in pairs(baseline) do
        if states.installed[name] and states.enabled[name] ~= nil and states.enabled[name] ~= was then n = n + 1 end
    end
    return n
end

function L.pendingText(n)
    if n <= 0 then return "No changes pending" end
    if n == 1 then return "1 change needs a reload" end
    return n .. " changes need a reload"
end

-- Rows for the options window: NectarKit (locked) first, then every entry; registered modules under their add-on.
function L.buildOptionsList(entries, states, baseline, modules)
    baseline = baseline or {}
    local rows = {}
    local function addModules(addon)
        if not modules then return end
        for _, m in ipairs(modules:forAddon(addon)) do
            rows[#rows + 1] = { kind = "module", addon = addon, key = m.key, label = m.label, on = m.on }
        end
    end
    rows[#rows + 1] = { kind = "addon", addon = L.SELF, title = L.SELF, installed = true, enabled = true, locked = true, pending = false }
    addModules(L.SELF)
    for _, e in ipairs(entries or {}) do
        local installed = states.installed[e.addon] and true or false
        local enabled = installed and states.enabled[e.addon] == true
        local was = baseline[e.addon]
        rows[#rows + 1] = { kind = "addon", addon = e.addon, title = e.title or e.addon, installed = installed,
            enabled = enabled, locked = false, pending = installed and was ~= nil and was ~= enabled }
        addModules(e.addon)
    end
    return rows
end

-- Module registry -------------------------------------------------------------
-- State lives in db.modules[addon][key] (booleans). getDB may return nil before NectarKit's DB exists.
-- Callbacks wait for login(); a module registered after login is called at once. Callbacks are pcall-guarded.
function L.newModules(getDB, onError)
    local R = { list = {}, byId = {}, loggedIn = false }

    local function db()
        local ok, d = pcall(getDB)
        if ok and type(d) == "table" then return d end
    end
    local function id(addon, key) return addon .. "\n" .. key end
    local function saved(addon, key)
        local d = db()
        local m = d and type(d.modules) == "table" and d.modules[addon]
        local v = nil
        if type(m) == "table" then v = m[key] end
        if type(v) == "boolean" then return v end
    end

    function R:isOn(addon, key)
        local m = type(addon) == "string" and type(key) == "string" and self.byId[id(addon, key)]
        if not m then return false end
        local v = saved(addon, key)
        if v ~= nil then return v end
        return m.default
    end

    local function fire(m)
        if type(m.onToggle) ~= "function" then return end
        local ok, err = pcall(m.onToggle, R:isOn(m.addon, m.key))
        if not ok and onError then pcall(onError, m.addon, m.key, err) end
    end

    function R:register(addon, key, label, default, onToggle)
        if type(addon) ~= "string" or addon == "" or type(key) ~= "string" or key == "" then return false end
        local m = self.byId[id(addon, key)]
        if not m then
            m = { addon = addon, key = key }
            self.byId[id(addon, key)] = m
            self.list[#self.list + 1] = m
        end
        m.label = type(label) == "string" and label ~= "" and label or key
        m.default = default ~= false
        m.onToggle = type(onToggle) == "function" and onToggle or nil
        if self.loggedIn then fire(m) end
        return self:isOn(addon, key)
    end

    function R:set(addon, key, on)
        local m = type(addon) == "string" and type(key) == "string" and self.byId[id(addon, key)]
        if not m then return false end
        local d = db()
        if not d then return false end
        on = on and true or false
        if self:isOn(addon, key) == on then return false end
        if type(d.modules) ~= "table" then d.modules = {} end
        if type(d.modules[addon]) ~= "table" then d.modules[addon] = {} end
        d.modules[addon][key] = on
        fire(m)
        return true
    end

    function R:login()
        self.loggedIn = true
        for _, m in ipairs(self.list) do fire(m) end
    end

    function R:forAddon(addon)
        local out = {}
        for _, m in ipairs(self.list) do
            if m.addon == addon then
                out[#out + 1] = { key = m.key, label = m.label, default = m.default, on = self:isOn(m.addon, m.key) }
            end
        end
        return out
    end

    return R
end

-- Registrations left in a global table by add-ons that loaded before NectarKit. Entries are
-- { addon=, key=, label=, default=, onToggle= }. The table is emptied. Returns how many were valid.
function L.drainQueue(reg, queue)
    local n = 0
    if type(queue) ~= "table" then return 0 end
    local items = {}
    for _, e in ipairs(queue) do items[#items + 1] = e end
    for k in pairs(queue) do queue[k] = nil end
    for _, e in ipairs(items) do
        if type(e) == "table" and type(e.addon) == "string" and e.addon ~= "" and type(e.key) == "string" and e.key ~= "" then
            pcall(reg.register, reg, e.addon, e.key, e.label, e.default, e.onToggle)
            n = n + 1
        end
    end
    return n
end

-- Ranks addon names by cost(name) (plain numbers only; nil, errors and secret values are skipped), highest first, at most limit.
function L.topAddons(names, cost, limit)
    local out = {}
    if type(names) ~= "table" or type(cost) ~= "function" then return out end
    for _, n in ipairs(names) do
        local ok, v = pcall(cost, n)
        if ok and type(v) == "number" then
            local okc = pcall(function() return v >= 0 end)
            if okc then out[#out + 1] = { name = n, value = v } end
        end
    end
    table.sort(out, function(a, b) return a.value > b.value end)
    for i = #out, (limit or 10) + 1, -1 do out[i] = nil end
    return out
end
