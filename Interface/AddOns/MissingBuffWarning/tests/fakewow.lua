-- Minimal fake WoW client for MissingBuffWarning tests (Lua 5.1 via lupa).
-- Models what matters: frames, regions, show/hide, anchors, secure buttons, combat lockdown
-- (touching a protected frame in combat raises an error, like ADDON_ACTION_BLOCKED would),
-- auras per unit, party/raid units, spells, timers and events.

FAKE = { frames = {}, timers = {}, printed = {}, events = {} }
COMBAT = false          -- InCombatLockdown()
INGROUP = false
SHIFT = false

local Obj = {}
Obj.__index = function(t, k)
    local v = rawget(Obj, k)
    if v ~= nil then return v end
    if type(k) == "string" and k:match("^%u") then
        return function(self) return self end   -- any other API method: harmless no-op
    end
    return nil
end

local function isProtected(f)
    if f._secure then return true end
    for _, c in ipairs(f._children or {}) do
        if c._isFrame and isProtected(c) then return true end
    end
    return false
end
FAKE.isProtected = isProtected

local function guard(self, what)
    if COMBAT and self._isFrame and isProtected(self) then
        error("BLOCKED in combat: " .. what .. " on protected frame " .. tostring(self._name or self._kind), 2)
    end
end

local function new(kind, parent, isFrame)
    local o = setmetatable({ _kind = kind, _shown = true, _points = {}, _children = {}, _scripts = {},
        _attr = {}, _alpha = 1, _scale = 1, _w = 0, _h = 0, _mouse = false, _isFrame = isFrame,
        _parent = parent, _events = {} }, Obj)
    if parent then parent._children[#parent._children + 1] = o end
    return o
end

-- regions and frames
function Obj:Show() guard(self, "Show"); self._shown = true end
function Obj:Hide() guard(self, "Hide"); self._shown = false end
function Obj:SetShown(v) if v then self:Show() else self:Hide() end end
function Obj:IsShown() return self._shown end
function Obj:IsVisible()
    local f = self
    while f do if not f._shown then return false end f = f._parent end
    return true
end
function Obj:SetPoint(...) guard(self, "SetPoint"); self._points[#self._points + 1] = { ... } end
function Obj:SetAllPoints(rel) guard(self, "SetAllPoints"); self._points = { { "ALL", rel } } end
function Obj:ClearAllPoints() guard(self, "ClearAllPoints"); self._points = {} end
function Obj:GetPoint(i) local p = self._points[i or 1]; if p then return unpack(p) end end
function Obj:SetSize(w, h) guard(self, "SetSize"); self._w, self._h = w, h end
function Obj:SetWidth(w) guard(self, "SetWidth"); self._w = w end
function Obj:SetHeight(h) guard(self, "SetHeight"); self._h = h end
function Obj:GetWidth() return self._w end
function Obj:GetHeight() return self._h end
function Obj:SetScale(s) guard(self, "SetScale"); self._scale = s end
function Obj:GetScale() return self._scale end
function Obj:SetAlpha(a) self._alpha = a end
function Obj:GetAlpha() return self._alpha end
function Obj:GetParent() return self._parent end
function Obj:SetParent(p) guard(self, "SetParent"); self._parent = p end
function Obj:GetRight() return 900 end
function Obj:GetTop() return 700 end
function Obj:GetBottom() return 600 end
function Obj:GetLeft() return 800 end
function Obj:GetCenter() return 850, 650 end
function Obj:GetEffectiveScale() return 1 end
function Obj:GetFrameLevel() return self._level or 1 end
function Obj:SetFrameLevel(l) self._level = l end
-- text / textures
function Obj:SetText(t) self._text = t end
function Obj:GetText() return self._text end
function Obj:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function Obj:SetTexture(t) self._texture = t end
function Obj:GetTexture() return self._texture end
function Obj:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
function Obj:SetVertexColor(r, g, b, a) self._vcolor = { r, g, b, a } end
function Obj:SetTextColor(r, g, b, a) self._tcolor = { r, g, b, a } end
function Obj:SetDesaturated(v) self._desat = v end
function Obj:GetStringWidth() return #(self._text or "") * 6 end
function Obj:GetStringHeight() return 12 end
function Obj:SetFont(path, size, flags) self._fontSize = size end
function Obj:GetFont() return "Fonts\\FRIZQT__.TTF", self._fontSize or 12, "" end
function Obj:SetBackdropColor(r, g, b, a) self._bdcolor = { r, g, b, a } end
function Obj:SetBackdropBorderColor(r, g, b, a) self._bdborder = { r, g, b, a } end
function Obj:SetBackdrop(b) self._backdrop = b end
-- frames only
function Obj:CreateTexture() return new("Texture", self, false) end
function Obj:CreateFontString() return new("FontString", self, false) end
function Obj:CreateAnimationGroup()
    local g = new("AnimationGroup", nil, false)
    g._playing = false
    g.Play = function(s) s._playing = true end
    g.Stop = function(s) s._playing = false end
    g.IsPlaying = function(s) return s._playing end
    g.CreateAnimation = function() return new("Animation", nil, false) end
    return g
end
function Obj:SetScript(ev, fn) self._scripts[ev] = fn end
function Obj:HookScript(ev, fn)
    local old = self._scripts[ev]
    self._scripts[ev] = function(...) if old then old(...) end fn(...) end
end
function Obj:GetScript(ev) return self._scripts[ev] end
function Obj:EnableMouse(v) guard(self, "EnableMouse"); self._mouse = v and true or false end
function Obj:IsMouseEnabled() return self._mouse end
function Obj:SetAttribute(k, v)
    if COMBAT and self._secure then error("BLOCKED in combat: SetAttribute " .. tostring(k), 2) end
    self._attr[k] = v
end
function Obj:GetAttribute(k) return self._attr[k] end
function Obj:RegisterForClicks(...) self._clicks = { ... } end
function Obj:RegisterEvent(e) self._events[e] = true end
function Obj:UnregisterEvent(e) self._events[e] = nil end
function Obj:RegisterUnitEvent(e) self._events[e] = true end
function Obj:SetChecked(v) self._checked = v and true or false end
function Obj:GetChecked() return self._checked end
function Obj:HasFocus() return false end
function Obj:IsPlaying() return false end
function Obj:GetNormalTexture() return new("Texture", self, false) end
function Obj:GetHighlightTexture() return new("Texture", self, false) end
function Obj:GetPushedTexture() return new("Texture", self, false) end
function Obj:SetFontObject(o) self._fontObject = o end
function Obj:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Obj:SetValue(v) self._value = v; local f = self._scripts.OnValueChanged; if f then f(self, v) end end
function Obj:GetValue() return self._value end
-- test helpers
function Obj:Click(button)
    local f = self._scripts.OnClick
    if f then f(self, button or "LeftButton") end
end

UIParent = new("Frame", nil, true)
UIParent._w, UIParent._h = 1920, 1080
Minimap = new("Frame", nil, true); Minimap._w = 140
GameTooltip = new("GameTooltip", UIParent, true)
GameTooltip._lines = {}
function GameTooltip:AddLine(t) self._lines[#self._lines + 1] = t end
function GameTooltip:SetOwner() self._lines = {} end
function GameTooltip:ClearLines() self._lines = {} end
GameTooltip.AddLine = function(s, t) s._lines[#s._lines + 1] = t end
GameTooltip.SetOwner = function(s) s._lines = {} end

function CreateFrame(kind, name, parent, template)
    local secure = template and template:find("Secure") ~= nil
    if secure and COMBAT then error("BLOCKED in combat: CreateFrame secure", 2) end
    local f = new(kind, parent, true)
    f._name, f._template, f._secure = name, template, secure
    if template and template:find("UICheckButton") then f._checked = false end
    if template and template:find("BasicFrameTemplate") then f.TitleText = f:CreateFontString() end
    if name then _G[name] = f end
    FAKE.frames[#FAKE.frames + 1] = f
    return f
end

function InCombatLockdown() return COMBAT end
function UnitAffectingCombat() return COMBAT end
function IsShiftKeyDown() return SHIFT end
function GetCursorPosition() return 0, 0 end
function GetCVar() return "0" end
function GetTime() return FAKE.now or 0 end
function hooksecurefunc() end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
tinsert = table.insert
UISpecialFrames = {}
SlashCmdList = {}
function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    FAKE.printed[#FAKE.printed + 1] = table.concat(t, " ")
end
C_Timer = { After = function(d, fn) FAKE.timers[#FAKE.timers + 1] = fn end,
            NewTicker = function() return { Cancel = function() end } end }
function FAKE.flushTimers()
    for _ = 1, 5 do
        local t = FAKE.timers; FAKE.timers = {}
        for _, fn in ipairs(t) do fn() end
        if #FAKE.timers == 0 then return end
    end
end

-- units, spells, auras
UNITS = { player = { name = "Me", class = "PRIEST" } }
AURAS = { player = {} }
SECRET = {}            -- SECRET[unit] = true: names come back hidden
KNOWN = {}             -- spell name -> { name, iconID, spellID, passive }
function UnitClass(u) local x = UNITS[u]; return x and x.class, x and x.class end
function UnitName(u) local x = UNITS[u]; return x and x.name end
function UnitExists(u) return UNITS[u] ~= nil end
function UnitIsConnected(u) local x = UNITS[u]; return x ~= nil and not x.offline end
function UnitIsDeadOrGhost(u) local x = UNITS[u]; return x ~= nil and x.dead == true end
function UnitOnTaxi(u) return UNITS[u] and UNITS[u].taxi == true end
function UnitIsUnit(a, b)
    if a == b then return true end
    local x, y = UNITS[a], UNITS[b]
    return (b == "player" and x and x.isPlayer) or (a == "player" and y and y.isPlayer) or false
end
function IsInGroup() return INGROUP end
function IsInRaid() return INGROUP == "raid" end
function GetNumGroupMembers()
    if not INGROUP then return 0 end
    local n = 0
    for u in pairs(UNITS) do if u ~= "player" then n = n + 1 end end
    return n + (INGROUP == "raid" and 0 or 1)
end
local SECRETVAL = setmetatable({}, { __tostring = function() return "<secret>" end })
function issecretvalue(v) return v == SECRETVAL end
C_UnitAuras = {
    GetAuraDataByIndex = function(unit, i)
        local list = AURAS[unit] or {}
        local n = list[i]
        if not n then return nil end
        if SECRET[unit] == "throw" then error("Auras cannot be accessed when secret while tainted") end
        if SECRET[unit] then return { name = SECRETVAL } end
        return { name = n }
    end,
}
C_Spell = {
    GetSpellInfo = function(x)
        local s = KNOWN[x]
        if not s and type(x) == "number" then
            for _, v in pairs(KNOWN) do if v.spellID == x then s = v end end
        end
        if s then return { name = s.name, iconID = s.iconID, spellID = s.spellID } end
    end,
    IsSpellPassive = function(id)
        for _, v in pairs(KNOWN) do if v.spellID == id then return v.passive == true end end
        return false
    end,
}
function FAKE.learn(name, id) KNOWN[name] = { name = name, iconID = 1000 + id, spellID = id } end

function FAKE.fire(event, ...)
    for _, f in ipairs(FAKE.frames) do
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end

-- find helpers
function FAKE.find(pred) for _, f in ipairs(FAKE.frames) do if pred(f) then return f end end end
function FAKE.all(pred)
    local out = {}
    for _, f in ipairs(FAKE.frames) do if pred(f) then out[#out + 1] = f end end
    return out
end
function FAKE.visibleSecure()
    return FAKE.all(function(f) return f._secure and f:IsVisible() end)
end
