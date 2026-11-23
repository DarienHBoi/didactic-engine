-- Banner (popup A): a Darkmoon Faire "Test Your Strength" carnival banner for new records, plus an "update ready" variant.
-- Created lazily on the first show. Animations are AnimationGroups only (no OnUpdate); the fade-out hides the frame.
local addonName, RB = ...
local L = RB.L

local Banner = {}
RB.Banner = Banner

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PURPLE, DARKER, GOLD = { 0.18, 0.07, 0.25 }, { 0.26, 0.11, 0.35 }, { 1, 0.82, 0.2 }
local W, H = 480, 104
local SHOW_SECONDS, FADE_SECONDS = 5, 1
-- Inferred, not verified on Forever: a built-in Classic bell sound; PlaySound(READY_CHECK / 8960) is the fallback.
local BELL_FILE = "Sound\\Doodad\\BellTollAlliance.ogg"

local frame, grip, puck, tower, texts, groups, iconBox, iconTex
local PUCK_BOTTOM, PUCK_TOP = 6, 42
local RED = { 0.75, 0.1, 0.1 }
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
local BODY_X_ICON, BODY_X_PLAIN = 108, 46
-- font sizes: the amount carries the most weight, then the name, then the detail line
local SIZE_NAME, SIZE_AMOUNT, SIZE_DETAIL, SIZE_BEAT, SIZE_RIBBON = 21, 38, 14, 11, 12

-- helpers ------------------------------------------------------------------------------------------------------------
local function commas(n)
    if type(n) ~= "number" then return tostring(n) end
    if n ~= n or n == math.huge or n == -math.huge then return "?" end
    local s = string.format("%.0f", math.floor(n + 0.5))
    local sign, digits = s:match("^(-?)(%d+)$")
    if not digits then return s end
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return sign .. (digits:gsub("^,", ""))
end

local function short(name)
    if type(name) ~= "string" then return "?" end
    return name:match("^([^%-]+)") or name
end

local function plain(v)
    if L and L.isSecret and L.isSecret(v) then return false end
    return true
end

local function plainNumber(v)
    return type(v) == "number" and plain(v) and v == v and v ~= math.huge and v ~= -math.huge
end

local function setFont(fs, size, flags)
    local path = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    pcall(fs.SetFont, fs, path, size, flags or "")
    pcall(fs.SetWordWrap, fs, false)  -- one line only: the client truncates instead of wrapping
    if fs.SetMaxLines then pcall(fs.SetMaxLines, fs, 1) end
end

local function spellIcon(spellID)
    if type(spellID) ~= "number" or not plain(spellID) or not (C_Spell and C_Spell.GetSpellTexture) then return FALLBACK_ICON end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    if ok and plain(tex) and (type(tex) == "number" or (type(tex) == "string" and tex ~= "")) then return tex end
    return FALLBACK_ICON
end

local function allowed(which)
    local o = RB.db and RB.db.options
    if o and o[which] == false then return false end
    if NectarKit_IsModuleOn and not NectarKit_IsModuleOn("RingTheBell", which) then return false end
    return true
end

local function playSound()
    if not allowed("sound") then return end
    local ok, willPlay = pcall(PlaySoundFile, BELL_FILE, "Master")
    if ok and willPlay ~= false then return end
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960)
end

-- frame --------------------------------------------------------------------------------------------------------------
local function rect(parent, layer, c, w, h, point, x, y)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(WHITE)
    t:SetVertexColor(c[1], c[2], c[3], 1)
    if w then t:SetSize(w, h) end
    if point then t:SetPoint(point, parent, point, x or 0, y or 0) end
    return t
end

local function move(g, dx, dy, order, dur)
    local a = g:CreateAnimation("Translation")  -- the group's parent region is the animated target
    a:SetOffset(dx, dy)
    a:SetDuration(dur)
    a:SetOrder(order)
    return a
end

local function build()
    local f = CreateFrame("Frame", "RingTheBellBanner", UIParent)
    f:SetSize(W, H)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:EnableMouse(false)  -- never swallow clicks; only the small grip below takes the mouse
    f:SetMovable(true)

    rect(f, "BACKGROUND", PURPLE):SetAllPoints(f)
    -- carnival stripes: lighter purple bars every other 22 px, gold rails top and bottom
    for i = 0, 10 do
        rect(f, "BACKGROUND", DARKER, 22, H - 8, "TOPLEFT", 4 + i * 44, -4)
    end
    rect(f, "BORDER", GOLD, nil, 4, "TOPLEFT", 0, 0):SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    rect(f, "BORDER", GOLD, nil, 4, "BOTTOMLEFT", 0, 0):SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

    -- hammer (left): handle + head
    local hammer = CreateFrame("Frame", nil, f)
    hammer:SetSize(30, 56)
    hammer:SetPoint("LEFT", f, "LEFT", 8, -6)
    rect(hammer, "ARTWORK", { 0.55, 0.35, 0.15 }, 6, 40, "BOTTOM", 0, 0)
    rect(hammer, "ARTWORK", GOLD, 26, 14, "TOP", 0, 0)

    -- tower (right): rail with a puck on it and a bell at the top
    tower = CreateFrame("Frame", nil, f)
    tower:SetSize(40, 70)
    tower:SetPoint("RIGHT", f, "RIGHT", -14, -2)
    rect(tower, "ARTWORK", { 0.1, 0.03, 0.15 }, 10, 54, "BOTTOM", 0, 0)
    rect(tower, "ARTWORK", GOLD, 24, 6, "BOTTOM", 0, 0)  -- base plate
    puck = rect(tower, "OVERLAY", { 1, 0.3, 0.2 }, 12, 8, "BOTTOM", 0, PUCK_BOTTOM)
    local bell = CreateFrame("Frame", nil, tower)
    bell:SetSize(22, 16)
    bell:SetPoint("TOP", tower, "TOP", 0, 2)
    rect(bell, "OVERLAY", GOLD, 22, 12, "TOP", 0, 0)    -- bell body
    rect(bell, "OVERLAY", GOLD, 6, 4, "BOTTOM", 0, 0)   -- clapper

    -- red ribbon over the top edge
    local ribbon = CreateFrame("Frame", nil, f)
    ribbon:SetSize(150, 20)
    ribbon:SetPoint("TOP", f, "TOP", 0, 12)
    rect(ribbon, "ARTWORK", GOLD, 150, 20, "CENTER", 0, 0)
    rect(ribbon, "OVERLAY", RED, 146, 16, "CENTER", 0, 0)
    local rtext = ribbon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rtext:SetPoint("CENTER", ribbon, "CENTER", 0, 0)
    rtext:SetTextColor(1, 1, 1)
    rtext:SetWidth(140)
    setFont(rtext, SIZE_RIBBON, "OUTLINE")

    -- spell icon: gold border, soft glow behind it
    iconBox = CreateFrame("Frame", nil, f)
    iconBox:SetSize(60, 60)
    iconBox:SetPoint("LEFT", f, "LEFT", 44, -2)
    local glow = iconBox:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(GLOW)
    glow:SetSize(104, 104)
    glow:SetPoint("CENTER", iconBox, "CENTER", 0, 0)
    pcall(glow.SetBlendMode, glow, "ADD")
    pcall(glow.SetVertexColor, glow, 1, 0.75, 0.2, 0.8)
    rect(iconBox, "BORDER", GOLD, 60, 60, "CENTER", 0, 0)
    iconTex = iconBox:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(56, 56)
    iconTex:SetPoint("CENTER", iconBox, "CENTER", 0, 0)
    iconTex:SetTexture(FALLBACK_ICON)
    pcall(iconTex.SetTexCoord, iconTex, 0.08, 0.92, 0.08, 0.92)

    local function fstring(size, flags, template)
        local fs = f:CreateFontString(nil, "OVERLAY", template)
        fs:SetJustifyH("LEFT")
        fs:SetWidth(W - 110 - 62)
        setFont(fs, size, flags)
        return fs
    end
    local name = fstring(SIZE_NAME, "OUTLINE", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", f, "TOPLEFT", BODY_X_ICON, -12)
    local amount = fstring(SIZE_AMOUNT, "OUTLINE", "GameFontNormalLarge")
    amount:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, 0)
    amount:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    pcall(amount.SetShadowColor, amount, 1, 0.7, 0, 0.55)
    pcall(amount.SetShadowOffset, amount, 2, -2)
    local detail = fstring(SIZE_DETAIL, nil, "GameFontHighlight")
    detail:SetPoint("TOPLEFT", amount, "BOTTOMLEFT", 0, -1)
    detail:SetTextColor(1, 0.95, 0.8)
    local beat = fstring(SIZE_BEAT, nil, "GameFontNormalSmall")
    beat:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, -1)
    beat:SetTextColor(0.73, 0.67, 0.67)
    texts = { ribbon = rtext, name = name, amount = amount, detail = detail, beat = beat }

    -- animation: hammer slams down, puck rises, bell shakes (Translation only: no Rotation support assumed on this client)
    local swing = hammer:CreateAnimationGroup()
    move(swing, -6, 10, 1, 0.15)
    move(swing, 6, -22, 2, 0.12)
    move(swing, 0, 12, 3, 0.25)
    local rise = puck:CreateAnimationGroup()
    local up = move(rise, 0, PUCK_TOP - PUCK_BOTTOM, 1, 0.7)
    up:SetStartDelay(0.27)
    -- a Translation reverts when its group ends, so re-anchor the puck at the top to keep it "rung" (reset on the next show)
    rise:SetScript("OnFinished", function()
        puck:ClearAllPoints()
        puck:SetPoint("BOTTOM", tower, "BOTTOM", 0, PUCK_TOP)
    end)
    local shake = bell:CreateAnimationGroup()
    for i = 1, 6 do move(shake, (i % 2 == 1) and 4 or -4, 0, i, 0.06) end

    -- fade: wait SHOW_SECONDS, fade out, then hide
    local fade = f:CreateAnimationGroup()
    local a = fade:CreateAnimation("Alpha")
    a:SetStartDelay(SHOW_SECONDS)
    a:SetDuration(FADE_SECONDS)
    if a.SetFromAlpha and a.SetToAlpha then a:SetFromAlpha(1); a:SetToAlpha(0) else a:SetChange(-1) end
    a:SetOrder(1)
    fade:SetScript("OnFinished", function() f:Hide(); f:SetAlpha(1) end)

    groups = { swing, rise, shake, fade }

    -- the grip is the only mouse-enabled part: drag it to move the banner
    grip = CreateFrame("Frame", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -8)
    rect(grip, "OVERLAY", GOLD, 16, 16, "CENTER", 0, 0)
    rect(grip, "OVERLAY", PURPLE, 10, 2, "CENTER", 0, 3)
    rect(grip, "OVERLAY", PURPLE, 10, 2, "CENTER", 0, -3)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() f:StartMoving() end)
    grip:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, relativePoint, x, y = f:GetPoint()
        local db = RB.db
        if db and point then
            if type(db.popup) ~= "table" then db.popup = {} end
            db.popup.point, db.popup.relativePoint, db.popup.x, db.popup.y = point, relativePoint, x, y
        end
    end)
    f:SetScript("OnHide", function(self) self:StopMovingOrSizing() end)
    f:Hide()
    frame = f
    return f
end

-- m = { ribbon, name, nameColor = {r,g,b}, amount, detail, beat, icon = texture or nil (no icon) }
local function present(m, bellAlways)
    if not allowed("popup") then
        if bellAlways then playSound() end  -- the bell has its own switch (playSound checks it)
        return
    end
    local f = frame or build()
    texts.ribbon:SetText(m.ribbon)
    texts.name:SetText(m.name)
    local c = m.nameColor or GOLD
    texts.name:SetTextColor(c[1], c[2], c[3])
    texts.amount:SetText(m.amount or "")
    texts.detail:SetText(m.detail or "")
    texts.beat:SetText(m.beat or "")
    if m.icon then
        iconTex:SetTexture(m.icon)
        iconBox:Show()
    else
        iconBox:Hide()
    end
    texts.name:ClearAllPoints()
    texts.name:SetPoint("TOPLEFT", f, "TOPLEFT", m.icon and BODY_X_ICON or BODY_X_PLAIN, -12)
    local pos = RB.db and RB.db.popup
    f:ClearAllPoints()
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
    grip:EnableMouse(not (InCombatLockdown and InCombatLockdown()))  -- decided at show time; no mouse in a fight
    for _, g in ipairs(groups) do g:Stop() end  -- a show while visible restarts everything
    puck:ClearAllPoints()
    puck:SetPoint("BOTTOM", tower, "BOTTOM", 0, PUCK_BOTTOM)
    f:SetAlpha(1)
    f:Show()
    for _, g in ipairs(groups) do g:Play() end
    playSound()
end

-- public -------------------------------------------------------------------------------------------------------------
function Banner.show(rec, prev)
    if type(rec) ~= "table" then return end
    local detail = tostring(rec.spell or "?") .. " · on " .. tostring(rec.target or "?")
    if plainNumber(rec.secs) and rec.secs > 0 then
        detail = detail .. " · " .. string.format("%d", math.floor(rec.secs + 0.5)) .. " s fight"
    end
    local beat
    if type(prev) == "table" and type(prev.player) == "string" and plainNumber(prev.amount) then
        beat = "beat " .. short(prev.player) .. "'s " .. commas(prev.amount)
    end
    local r, g, b = 1, 0.82, 0
    if L and L.classColor then r, g, b = L.classColor(rec.class) end
    present({
        ribbon = "NEW RECORD", name = short(rec.player), nameColor = { r, g, b },
        amount = commas(rec.amount), detail = detail, beat = beat, icon = spellIcon(rec.spellID),
    }, true)
end

function Banner.showUpdate(sender, theirVer, myVer)
    if sender == nil then return end
    present({
        ribbon = "UPDATE READY", name = short(sender), amount = tostring(theirVer),
        detail = "has Ring the Bell " .. tostring(theirVer) .. ", you have " .. tostring(myVer),
    })
end

RB.onRecord = function(rec, prev, fromSelf) Banner.show(rec, prev) end
