-- Reaper widgets: a small Shadow Word: Death icon on the plate, an optional thin kill tick, and an optional soft glow
-- over the SW:D action button. No text, no centre-screen alert, no colour flood.
-- UnitHealth / UnitHealthMax are SECRET in combat: they only ever go into StatusBars (SetMinMaxValues / SetValue);
-- the widget does the comparing by geometry. Never compare them or do arithmetic on them here.
-- Techniques (DoesItDie Nameplates.lua kill icon):
--   * Flag ("is health at or below X?"): a clipping window holds a bar of huge length, right edge on the window, with
--     max = current health and value = X. The picture rides the fill's right edge, so it is inside the window only
--     when X >= health (the fill is full); otherwise it slides far out of view.
--   * Tick at a health amount: an invisible bar with max = max health and value = the amount; a 1 px texture sits on
--     its fill's right edge.
--   * Gate ("is health ABOVE X?"), the inverse flag: a clipping frame spans the UNFILLED part of a long bar (from the
--     fill's right edge to the bar's right end), with max = current health and value = X. Pictures at the bar's right
--     end are inside it while X < health and vanish when X >= health (the frame then has no width).
-- Icon: a dim grey copy at the soon line (SW:D in range within about 2 s), and the coloured icon with a glow ring and
-- an alpha pulse (0.8 to 1, about 1 s) at the kill line. Both are flags inside the gate at the finish line (your DoTs
-- kill it within 1.5 s by themselves): then they vanish and a tiny grey dot (a flag at the same line) shows instead.
local _, R = ...
local W = {}
R.Widgets = W

local WHITE = "Interface\\Buttons\\WHITE8X8"
W.FALLBACK_ICON = "Interface\\Icons\\Spell_Shadow_DemonicFortitude" -- Shadow Word: Death
local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local BAR_LENGTH = 10000
local FALLBACK_LEVEL = 200
W.READY_ALPHA = 0.7                      -- dim, desaturated "soon" icon
W.PULSE_FROM, W.PULSE_TO, W.PULSE_SECONDS = 0.8, 1, 1.0
W.KILL_GLOW_ALPHA = 0.9                  -- ring around the kill icon
W.DOT_SIZE, W.DOT_ALPHA = 5, 0.75        -- "your DoTs finish it" dot
W.TICK_ALPHA = 0.7
W.GLOW_ALPHA = 0.55                      -- button glow, gentle
local GLOW_SCALE = 1.7                   -- the border texture's glow ring is drawn larger than the button

local function isNum(v)
    if type(issecretvalue) == "function" then
        local ok, s = pcall(issecretvalue, v)
        if ok and s then return false end
    end
    return type(v) == "number"
end

local function invisibleBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    return bar
end

-- A clipping window with a long bar; a picture of the window's size rides the fill's right edge.
local function flagWindow(parent, layer, sub)
    local win = CreateFrame("Frame", nil, parent)
    win:SetClipsChildren(true)
    local bar = invisibleBar(win)
    bar:SetPoint("RIGHT", win, "RIGHT")
    -- on the bar (a child frame of the window), exactly like DoesItDie's kill icon, so the window clips it
    local tex = bar:CreateTexture(nil, layer or "OVERLAY", nil, sub or 0)
    tex:SetPoint("RIGHT", bar:GetStatusBarTexture(), "RIGHT")
    return win, bar, tex
end

-- The inverse flag: returns the long bar and the clipping frame on its unfilled part (see the top of the file).
local function gate(parent)
    local bar = invisibleBar(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:SetClipsChildren(true)
    g:SetPoint("LEFT", bar:GetStatusBarTexture(), "RIGHT")
    g:SetPoint("RIGHT", bar, "RIGHT")
    return bar, g
end

local function sizeGate(bar, g, height)
    bar:SetSize(BAR_LENGTH, height)
    g:SetHeight(height)
end

local function pulse(tex)
    local ok, group = pcall(function()
        local g = tex:CreateAnimationGroup()
        g:SetLooping("BOUNCE")
        local a = g:CreateAnimation("Alpha")
        a:SetFromAlpha(W.PULSE_FROM)
        a:SetToAlpha(W.PULSE_TO)
        a:SetDuration(W.PULSE_SECONDS)
        g:Play()
        return g
    end)
    return ok and group or nil
end

local function setFlag(bar, health, x)
    bar:SetMinMaxValues(0, health)
    bar:SetValue(x)
end

-- Plate (or target frame) widgets ---------------------------------------------------------------------------------
local function create(host)
    local w = { host = host }
    w.root = CreateFrame("Frame", nil, host)

    w.tickBar = invisibleBar(w.root)
    w.tickBar:SetAllPoints(w.root)
    w.tick = w.root:CreateTexture(nil, "OVERLAY")
    w.tick:SetColorTexture(1, 1, 1, W.TICK_ALPHA)
    w.tick:SetWidth(1)
    w.tick:SetPoint("TOPRIGHT", w.tickBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    w.tick:SetPoint("BOTTOMRIGHT", w.tickBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)

    w.icons = CreateFrame("Frame", nil, w.root)
    w.icons:SetAllPoints(w.root)
    w.gateBar, w.gate = gate(w.icons)
    w.readyWin, w.readyBar, w.readyIcon = flagWindow(w.gate, "OVERLAY", 0)
    w.readyIcon:SetAlpha(W.READY_ALPHA)
    pcall(w.readyIcon.SetDesaturated, w.readyIcon, true)
    w.killWin, w.killBar, w.killIcon = flagWindow(w.gate, "OVERLAY", 2)
    w.killIcon:ClearAllPoints() -- re-placed by setSize, inside the ring's margin
    w.killGlow = w.killBar:CreateTexture(nil, "OVERLAY", nil, 1)
    w.killGlow:SetTexture(GLOW_TEXTURE)
    pcall(w.killGlow.SetBlendMode, w.killGlow, "ADD")
    w.killGlow:SetVertexColor(0.8, 0.6, 1, W.KILL_GLOW_ALPHA)
    w.killGlow:SetPoint("CENTER", w.killIcon, "CENTER")
    w.pulse = pulse(w.killIcon)
    w.glowPulse = pulse(w.killGlow)
    w.dotWin, w.dotBar, w.dot = flagWindow(w.icons, "OVERLAY", 0)
    w.dot:SetColorTexture(0.6, 0.6, 0.6, W.DOT_ALPHA)
    W.setIcon(w, W.FALLBACK_ICON)
    W.setSize(w, 17)

    -- A recycled (pooled) host must not show the last mob's icon before the next update.
    pcall(function() host:HookScript("OnHide", function() w.root:Hide() end) end)
    return w
end

function W.setIcon(w, texture)
    if texture == nil or w.texture == texture then return end
    w.texture = texture
    w.readyIcon:SetTexture(texture)
    w.killIcon:SetTexture(texture)
end

-- The icons sit above the right end of the bar (DoesItDie's icon is left by default; Forever's level badge is right).
-- The kill window is wider by the glow ring's margin on each side, centred on the same spot.
function W.setSize(w, size)
    if w.size == size then return end
    w.size = size
    local pad = math.ceil(size * 0.35)
    local outer = size + 2 * pad
    w.readyWin:SetSize(size, size); w.readyBar:SetSize(BAR_LENGTH, size); w.readyIcon:SetSize(size, size)
    w.killWin:SetSize(outer, outer); w.killBar:SetSize(BAR_LENGTH, outer); w.killIcon:SetSize(size, size)
    w.killIcon:ClearAllPoints()
    w.killIcon:SetPoint("RIGHT", w.killBar:GetStatusBarTexture(), "RIGHT", -pad, 0)
    w.killGlow:SetSize(outer, outer)
    sizeGate(w.gateBar, w.gate, outer)
    for _, f in ipairs({ w.readyWin, w.killWin, w.gateBar }) do f:ClearAllPoints() end
    w.readyWin:SetPoint("BOTTOMRIGHT", w.root, "TOPRIGHT", 0, 3)
    w.killWin:SetPoint("BOTTOMRIGHT", w.root, "TOPRIGHT", pad, 3 - pad)
    w.gateBar:SetPoint("BOTTOMRIGHT", w.root, "TOPRIGHT", pad, 3 - pad)
    local d, inset = W.DOT_SIZE, math.floor((size - W.DOT_SIZE) / 2)
    w.dotWin:SetSize(d, d); w.dotBar:SetSize(BAR_LENGTH, d); w.dot:SetSize(d, d)
    w.dotWin:ClearAllPoints()
    w.dotWin:SetPoint("BOTTOMRIGHT", w.root, "TOPRIGHT", -inset, 3 + inset)
end

-- Puts the widgets over a health bar and layers them above it. Level and strata can be secret in Forever.
-- matchStrata: a plate addon's bar (EllesmereUI) is drawn in a strata of its own, which ours must match.
function W.attach(w, bar, matchStrata)
    w.bar = bar
    w.root:ClearAllPoints()
    w.root:SetAllPoints(bar)
    if matchStrata then
        local ok, strata = pcall(bar.GetFrameStrata, bar)
        if ok and type(strata) == "string" and not (issecretvalue and issecretvalue(strata)) then
            w.root:SetFrameStrata(strata)
        end
    end
    local ok, level = pcall(bar.GetFrameLevel, bar)
    if not ok or not isNum(level) then level = FALLBACK_LEVEL end
    w.root:SetFrameLevel(level + 20) -- above plate decorations, like DoesItDie's icon
end

function W.new(host, bar, matchStrata)
    local w = create(host)
    W.attach(w, bar, matchStrata)
    return w
end

function W.hide(w)
    w.root:Hide()
end

-- Draws one unit. maxHealth and health may be secret (they only go into StatusBars); kill, ready (soon) and finish
-- are plain health amounts (finish nil = nothing finishes it).
-- opts = { icon = bool, tick = bool, size = px, texture = path or file id }. Returns true, or false and the error.
function W.draw(w, maxHealth, health, kill, ready, finish, opts)
    if kill == nil or not (opts.icon or opts.tick) then
        w.root:Hide()
        return true
    end
    ready = ready or kill
    local ok, err = pcall(function()
        W.setIcon(w, opts.texture)
        W.setSize(w, opts.size or 17)
        w.tickBar:SetMinMaxValues(0, maxHealth)
        w.tickBar:SetValue(kill)
        setFlag(w.readyBar, health, ready)
        setFlag(w.killBar, health, kill)
        setFlag(w.gateBar, health, finish or 0)
        setFlag(w.dotBar, health, finish or 0)
    end)
    if not ok then
        w.root:Hide()
        return false, err
    end
    w.root:Show()
    w.icons:SetShown(opts.icon and true or false)
    w.tick:SetShown(opts.tick and true or false)
    return true
end

-- Action button glow -----------------------------------------------------------------------------------------------
-- Our own frame (parent UIParent) laid over the button; the button itself is never written to, and Blizzard's
-- overlay glow functions are never called. The glow is a flag window too: visible only when health <= ready.
function W.newGlow()
    local g = {}
    g.frame = CreateFrame("Frame", nil, UIParent)
    g.frame:SetFrameStrata("HIGH")
    g.gateBar, g.gate = gate(g.frame)
    g.gateBar:SetPoint("RIGHT", g.frame, "RIGHT")
    g.win, g.bar, g.tex = flagWindow(g.gate, "OVERLAY", 0)
    g.win:SetAllPoints(g.frame)
    g.tex:SetTexture(GLOW_TEXTURE)
    pcall(g.tex.SetBlendMode, g.tex, "ADD")
    g.tex:SetVertexColor(0.75, 0.55, 1, W.GLOW_ALPHA) -- soft shadow-violet
    g.pulse = pulse(g.tex)
    g.frame:Hide()
    return g
end

local function sizeOf(f)
    local okW, bw = pcall(f.GetWidth, f)
    local okH, bh = pcall(f.GetHeight, f)
    if not okW or not isNum(bw) or bw <= 0 then bw = 36 end
    if not okH or not isNum(bh) or bh <= 0 then bh = bw end
    return bw, bh
end

-- Lays the glow over a button (done out of combat, when the buttons are scanned).
function W.placeGlow(g, button)
    g.button = button
    g.frame:ClearAllPoints()
    g.frame:SetPoint("CENTER", button, "CENTER")
    local bw, bh = sizeOf(button)
    local gw, gh = math.floor(bw * GLOW_SCALE + 0.5), math.floor(bh * GLOW_SCALE + 0.5)
    g.frame:SetSize(gw, gh)
    g.bar:SetSize(BAR_LENGTH, gh)
    g.tex:SetSize(gw, gh)
    sizeGate(g.gateBar, g.gate, gh)
end

-- health may be secret; ready and finish are plain. nil ready hides it; no glow when your DoTs finish it.
function W.showGlow(g, health, ready, finish)
    if ready == nil then g.frame:Hide(); return true end
    local ok, err = pcall(function()
        setFlag(g.bar, health, ready)
        setFlag(g.gateBar, health, finish or 0)
    end)
    if not ok then g.frame:Hide(); return false, err end
    g.frame:Show()
    return true
end

function W.hideGlow(g)
    g.frame:Hide()
end
