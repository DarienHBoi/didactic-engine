local ADDON, ns = ...

----------------------------------------------------------------------
-- Data: built-in class buffs. `auras` = aura names that count as "up"
-- (group versions included). `spell` is used to look up the icon and to
-- check that your character actually knows the spell.
----------------------------------------------------------------------
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

ns.BUILTIN = {
    PRIEST = {
        { key = "INNERFIRE",  label = "Inner Fire",            spell = "Inner Fire",
          auras = { "Inner Fire" }, icon = "Interface\\Icons\\Spell_Holy_InnerFire", default = true },
        { key = "FORTITUDE",  label = "Power Word: Fortitude", spell = "Power Word: Fortitude",
          auras = { "Power Word: Fortitude", "Prayer of Fortitude" },
          icon = "Interface\\Icons\\Spell_Holy_WordFortitude", default = true },
        { key = "SPIRIT",     label = "Divine Spirit",         spell = "Divine Spirit",
          auras = { "Divine Spirit", "Prayer of Spirit" },
          icon = "Interface\\Icons\\Spell_Holy_DivineSpirit", default = false },
        { key = "SHADOWPROT", label = "Shadow Protection",     spell = "Shadow Protection",
          auras = { "Shadow Protection", "Prayer of Shadow Protection" },
          icon = "Interface\\Icons\\Spell_Shadow_AntiShadow", default = false },
        { key = "SHADOWFORM", label = "Shadowform",            spell = "Shadowform",
          auras = { "Shadowform" }, icon = "Interface\\Icons\\Spell_Shadow_Shadowform", default = false },
    },
}

----------------------------------------------------------------------
-- Saved variables
----------------------------------------------------------------------
function ns.InitDB()
    MissingBuffWarningDB = MissingBuffWarningDB or {}
    local db = MissingBuffWarningDB
    if db.scale == nil then db.scale = 1 end
    if db.locked == nil then db.locked = true end
    db.classes = db.classes or {}
    ns.db = db
end

function ns.ClassConfig(class)
    local c = ns.db.classes[class]
    if not c then
        c = { enabled = {}, manual = {} }
        ns.db.classes[class] = c
    end
    c.enabled = c.enabled or {}
    c.manual = c.manual or {}
    return c
end

function ns.IsBuiltinEnabled(class, entry)
    local v = ns.ClassConfig(class).enabled[entry.key]
    if v == nil then return entry.default end
    return v
end

function ns.PlayerClass()
    local _, class = UnitClass("player")
    return class
end

----------------------------------------------------------------------
-- Pure logic (no UI) - easy to test
----------------------------------------------------------------------
-- Returns name, iconID, spellID for a known spell (name or id), else nil.
function ns.ResolveSpell(nameOrId)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, nameOrId)
        if ok and info then return info.name, info.iconID, info.spellID end
    end
    return nil
end

-- Passive spells (racial passives etc.) cannot be cast, so they get no click button.
function ns.IsPassive(spellID)
    if not spellID then return false end
    if C_Spell and C_Spell.IsSpellPassive then
        local ok, r = pcall(C_Spell.IsSpellPassive, spellID)
        if ok then return r and true or false end
    end
    if IsPassiveSpell then
        local ok, r = pcall(IsPassiveSpell, spellID)
        if ok then return r and true or false end
    end
    return false
end

-- Build the list of buffs to watch for this class.
function ns.BuildTracked(class, resolve)
    local out, seen = {}, {}
    local cfg = ns.ClassConfig(class)
    for _, e in ipairs(ns.BUILTIN[class] or {}) do
        if ns.IsBuiltinEnabled(class, e) then
            local name, icon = resolve(e.spell)
            -- only watch spells this character has learned
            if name then
                seen[string.lower(e.label)] = true
                out[#out + 1] = { label = e.label, auras = e.auras, icon = icon or e.icon, castable = true }
            end
        end
    end
    for _, m in ipairs(cfg.manual) do
        if m.enabled ~= false then
            local name, icon, sid = resolve(tonumber(m.input) or m.input)
            -- "Name(Rank 1)" / "Name (Racial Passive)": the buff itself is just "Name"
            local plain = (string.gsub(m.input, "%s*%b()", ""))
            if not name and plain ~= "" and plain ~= m.input then name, icon, sid = resolve(plain) end
            local passive = name ~= nil and ns.IsPassive(sid)
            local label = name or m.input
            -- same spell added twice (by name and by ID, or also built in): warn once
            if not seen[string.lower(label)] then
                seen[string.lower(label)] = true
                local auras = { label }
                if m.input ~= label then auras[#auras + 1] = m.input end
                if plain ~= "" and plain ~= label and plain ~= m.input then auras[#auras + 1] = plain end
                out[#out + 1] = { label = label, auras = auras, icon = icon or QUESTION,
                                  castable = (name ~= nil) and not passive,   -- known, non-passive only
                                  passive = passive }
            end
        end
    end
    return out
end

-- tracked: list from BuildTracked; have: set of aura names currently up.
function ns.FindMissing(tracked, have)
    local missing = {}
    for _, t in ipairs(tracked) do
        local found = false
        for _, a in ipairs(t.auras) do
            if have[a] then found = true break end
        end
        if not found then missing[#missing + 1] = t end
    end
    return missing
end

-- Set of the player's current helpful aura names, or nil if the API is missing.
function ns.ReadPlayerBuffs()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local have, secret, total, hidden = {}, false, 0, 0
    for i = 1, 100 do
        -- The call itself can throw "Auras cannot be accessed when secret while tainted"
        -- (boss encounters). Treat that like hidden names: leave the display unchanged.
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then
            return have, true, total, hidden + 1
        end
        if not a then break end
        total = total + 1
        local n = a.name
        if n and issecretvalue and issecretvalue(n) then
            secret = true            -- the game is hiding this aura's name (combat rules)
            hidden = hidden + 1
        elseif n then
            have[n] = true
        end
    end
    return have, secret, total, hidden
end

----------------------------------------------------------------------
-- Warning frame
----------------------------------------------------------------------
local SLOT, PANEL_H, ICON = 300, 110, 72   -- one warning panel: width, height; icon size
local GAP = SLOT + 14             -- centre-to-centre distance between warnings
local box, handle
local slots = {}
ns.slots = slots

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

-- Shift-drag a live warning to move it, shift-scroll to scale it (any time it is shown).
-- Not in combat: the game blocks moving frames that hold click-to-cast buttons then.
local function makeMovable(f)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        if IsShiftKeyDown() or not ns.db.locked then box:StartMoving(); ns.moving = true end
    end)
    f:SetScript("OnDragStop", function()
        if not ns.moving then return end
        ns.moving = false
        box:StopMovingOrSizing()
        ns.SavePosition()
        ns.ApplyPosition()
    end)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if InCombatLockdown() or not (IsShiftKeyDown() or not ns.db.locked) then return end
        ns.SetScaleKeepCorner(clamp(ns.db.scale + delta * 0.05, 0.4, 4))
    end)
end

function ns.SetScaleKeepCorner(sc)
    local s0 = box:GetScale()
    local right, top = box:GetRight() * s0, box:GetTop() * s0
    box:SetScale(sc)
    box:ClearAllPoints()
    box:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right / sc, top / sc)
    ns.db.scale = sc
    ns.SavePosition()
    if ns.OnScaleChanged then ns.OnScaleChanged(sc) end
end

-- One warning = a dark-brown WoW info panel: bronze border, gold title (buff name),
-- white body text, and the full-colour spell icon on the left.
local function getSlot(key)
    local s = slots[key]
    if s then return s end
    s = CreateFrame("Frame", nil, box, "BackdropTemplate")
    s:SetSize(SLOT, PANEL_H)
    s:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    s:SetBackdropColor(0.09, 0.075, 0.06, 0.96)
    s:SetBackdropBorderColor(0.55, 0.43, 0.28, 1)
    s:EnableMouse(true)
    makeMovable(s)

    -- full-colour spell icon on the left, in a bronze frame
    s.markBox = CreateFrame("Frame", nil, s, "BackdropTemplate")
    s.markBox:SetSize(ICON + 10, ICON + 10)
    s.markBox:SetPoint("LEFT", s, "LEFT", 16, 0)
    s.markBox:SetBackdrop({ edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 14 })
    s.markBox:SetBackdropBorderColor(0.7, 0.55, 0.3, 1)
    s.mark = s:CreateTexture(nil, "ARTWORK")
    s.mark:SetSize(ICON, ICON)
    s.mark:SetPoint("CENTER", s.markBox, "CENTER", 0, 0)
    s.mark:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    s.text = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")   -- gold title
    s.text:SetPoint("TOPLEFT", s, "TOPLEFT", ICON + 40, -24)
    s.text:SetJustifyH("LEFT")
    s.text:SetTextColor(1, 0.82, 0)
    s.text:SetWordWrap(false)
    s.text:SetWidth(SLOT - ICON - 56)

    s.body = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")     -- white text
    s.body:SetPoint("TOPLEFT", s.text, "BOTTOMLEFT", 0, -8)
    s.body:SetWidth(SLOT - ICON - 56)
    s.body:SetJustifyH("LEFT")
    s.body:SetTextColor(1, 1, 1)

    s.ag = s:CreateAnimationGroup()
    s.ag:SetLooping("BOUNCE")
    local a = s.ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.6)     -- never fades out, so it can't look like it flickers away
    a:SetDuration(0.8)
    a:SetSmoothing("IN_OUT")
    slots[key] = s
    return s
end

-- Click-to-cast: a transparent secure button over the panel, one per buff (not per position).
-- The game forbids creating or changing secure buttons in combat, so this only happens out
-- of combat; a buff that first shows up in combat gets its button at the next refresh after.
local function attachCast(s, entry)
    if s.cast or not entry.castable or InCombatLockdown() then return end
    local ok, btn = pcall(CreateFrame, "Button", nil, s, "SecureActionButtonTemplate")
    if not (ok and btn) then ns.castError = tostring(btn); return end
    btn:SetAllPoints(s)
    btn:SetFrameLevel(s:GetFrameLevel() + 5)
    -- both: the game picks key-down or key-up from the "cast on key press" setting
    btn:RegisterForClicks("AnyUp", "AnyDown")
    makeMovable(btn)
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", entry.label)   -- cast by name (highest rank)
    btn:SetAttribute("unit", "player")       -- on yourself
    s.cast = btn
end

function ns.ShowSlots(list)
    local n = #list
    local inList = {}
    for i = 1, n do
        local e = list[i]
        local s = getSlot(e.label)
        inList[e.label] = true
        s.mark:SetTexture(e.icon)
        s.text:SetText(e.label)
        attachCast(s, e)
        s.body:SetText("Your " .. e.label .. " is missing.\n"
            .. (e.passive and "It is a passive effect: it cannot be cast."
                or (s.cast and "Click here to cast it." or "Cast it to dismiss this warning.")))
        -- while unlocked the panel must be draggable, so the cast button lets the mouse through
        if s.cast and not InCombatLockdown() then s.cast:EnableMouse(ns.db.locked and true or false) end
        s:ClearAllPoints()
        s:SetPoint("CENTER", box, "CENTER", (i - (n + 1) / 2) * GAP, 0)
        s:Show()
        if not s.ag:IsPlaying() then s.ag:Play() end
    end
    for label, s in pairs(slots) do
        if not inList[label] then
            s.ag:Stop()
            s:Hide()
        end
    end
end

function ns.ApplyPosition()
    local sc = ns.db.scale
    box:SetScale(sc)
    box:ClearAllPoints()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local x, y = ns.db.x, ns.db.y
    -- ignore a saved position that is off the screen (resolution / UI scale changed)
    if x and y and w and h and (x > w or y > h or x < 0 or y < 0) then
        ns.db.x, ns.db.y, x, y = nil, nil, nil, nil
    end
    if x and y then
        -- x,y = screen position of the frame's top-right corner (UIParent units)
        box:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x / sc, y / sc)
    else
        box:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
end

function ns.SavePosition()
    local sc = box:GetScale()
    local r, t = box:GetRight(), box:GetTop()
    if r and t then ns.db.x, ns.db.y = r * sc, t * sc end
end

function ns.SetLocked(locked)
    ns.db.locked = locked and true or false
    local unlocked = not ns.db.locked
    box:EnableMouse(unlocked)
    box.bg:SetShown(unlocked)
    box.hint:SetShown(unlocked)
    handle:SetShown(unlocked)
    ns.Refresh()
end

function ns.ResetLayout()
    ns.db.scale, ns.db.x, ns.db.y = 1, nil, nil
    ns.ApplyPosition()
end

local function buildFrame()
    box = CreateFrame("Frame", "MissingBuffWarningFrame", UIParent)
    box:SetSize(SLOT, PANEL_H)
    box:SetFrameStrata("HIGH")
    box:SetClampedToScreen(true)
    box:SetMovable(true)
    box:RegisterForDrag("LeftButton")

    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bg:SetColorTexture(0, 0, 0, 0.45)
    box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.hint:SetPoint("BOTTOM", box, "TOP", 0, 4)
    box.hint:SetText("Drag to move - drag corner to resize")

    box:SetScript("OnDragStart", function(self)
        if not ns.db.locked then self:StartMoving() end
    end)
    box:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.SavePosition()
        ns.ApplyPosition()
    end)

    -- bottom-left resize handle, scales live; top-right corner stays put
    handle = CreateFrame("Button", nil, box)
    handle:SetSize(20, 20)
    handle:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
    handle:SetFrameLevel(box:GetFrameLevel() + 10)
    handle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    handle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    handle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    for _, getter in ipairs({ "GetNormalTexture", "GetHighlightTexture", "GetPushedTexture" }) do
        local tex = handle[getter](handle)
        if tex then tex:SetTexCoord(1, 0, 0, 1) end -- mirror grabber to the bottom-left
    end
    handle:SetScript("OnMouseDown", function(self)
        local es = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        local sx, sy = cx / es, cy / es
        local s0 = box:GetScale()
        local right, top = box:GetRight() * s0, box:GetTop() * s0
        local size0 = SLOT * s0
        self:SetScript("OnUpdate", function()
            local mx, my = GetCursorPosition()
            mx, my = mx / es, my / es
            local d = ((sx - mx) + (sy - my)) / 2 -- left/down = bigger
            local sc = clamp((size0 + d) / SLOT, 0.4, 4)
            box:SetScale(sc)
            box:ClearAllPoints()
            box:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right / sc, top / sc)
            ns.db.scale = sc
            if ns.OnScaleChanged then ns.OnScaleChanged(sc) end
        end)
    end)
    handle:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        ns.SavePosition()
    end)

    box.bg:Hide(); box.hint:Hide(); handle:Hide()

    -- holding shift shows the resize handle on a live warning
    local mod = CreateFrame("Frame")
    mod:RegisterEvent("MODIFIER_STATE_CHANGED")
    mod:SetScript("OnEvent", function()
        if ns.db and ns.db.locked then
            local any = false
            for _, sl in pairs(slots) do if sl:IsShown() then any = true end end
            handle:SetShown(IsShiftKeyDown() and any and not InCombatLockdown())
        end
    end)
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
local function refreshReal()
    if not (ns.db and box) then return end
    local class = ns.PlayerClass()
    local tracked = ns.BuildTracked(class, ns.ResolveSpell)
    local list = {}
    if not ns.db.locked then
        -- layout preview while unlocked
        for i = 1, math.min(2, #tracked) do list[i] = tracked[i] end
        if #list == 0 then list[1] = { label = "Example Buff", icon = QUESTION } end
    elseif not (UnitIsDeadOrGhost("player") or UnitOnTaxi("player")) then
        -- shown the whole time a tracked buff is missing, in combat too
        local have, secret = ns.ReadPlayerBuffs()
        if not have then return end
        ns.db.diag = nil   -- drop the temporary diagnostics saved by an earlier build
        -- if the game hides some buff names right now we can't tell: keep what is on screen
        if secret then return end
        list = ns.FindMissing(tracked, have)
    end
    ns.ShowSlots(list)
end

-- Errors are printed once to chat instead of failing silently (script errors are often hidden).
local lastErr
function ns.Refresh()
    local ok, err = pcall(refreshReal)
    if not ok and err ~= lastErr then
        lastErr = err
        print("|cffff4444MissingBuffWarning error:|r " .. tostring(err))
    end
    return ok
end

-- /mbw test: show two sample warnings for a few seconds, whatever buffs you have
function ns.TestFlash()
    local ok, err = pcall(ns.ShowSlots, {
        { label = "Inner Fire", icon = "Interface\\Icons\\Spell_Holy_InnerFire" },
        { label = "Power Word: Fortitude", icon = "Interface\\Icons\\Spell_Holy_WordFortitude" },
    })
    if ok then
        print("|cffffd200MBW|r test warning shown for 8 seconds.")
        C_Timer.After(8, ns.Refresh)
    else
        print("|cffff4444MissingBuffWarning error:|r " .. tostring(err))
    end
end

local pending
function ns.QueueRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.25, function() pending = false; ns.Refresh() end)
end

----------------------------------------------------------------------
-- Events and slash commands
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        ns.InitDB()
        buildFrame()
        ns.ApplyPosition()
        ns.SetLocked(ns.db.locked)
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("PLAYER_DEAD")
        self:RegisterEvent("PLAYER_ALIVE")
        self:RegisterEvent("PLAYER_UNGHOST")
        self:RegisterEvent("SPELLS_CHANGED")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterUnitEvent("UNIT_AURA", "player")
        -- safety net: re-check once a second so the warning can never get stuck hidden
        local elapsed = 0
        self:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed >= 1 then elapsed = 0; ns.Refresh() end
        end)
    else
        ns.QueueRefresh()
    end
end)

SLASH_MISSINGBUFFWARNING1 = "/mbw"
SLASH_MISSINGBUFFWARNING2 = "/missingbuff"
SlashCmdList["MISSINGBUFFWARNING"] = function(msg)
    msg = string.lower(strtrim and strtrim(msg or "") or (msg or ""))
    if msg == "unlock" then
        ns.SetLocked(false)
    elseif msg == "lock" then
        ns.SetLocked(true)
    elseif msg == "reset" then
        ns.ResetLayout()
    elseif msg == "test" then
        ns.TestFlash()
    elseif msg == "linkdebug" then
        ns.linkDebug = not ns.linkDebug
        print("|cffffd200MBW|r linkdebug " .. (ns.linkDebug and "ON" or "OFF")
            .. ". Hooks installed: " .. (#(ns.linkHooks or {}) > 0 and table.concat(ns.linkHooks, ", ") or "NONE")
            .. ". Click the Add box, then shift-click a spell.")
    elseif msg == "debug" then
        local dbgLines = {}
        local function dprint(t) print(t); dbgLines[#dbgLines + 1] = t end
        local class = ns.PlayerClass()
        dprint("|cffffd200MBW debug|r class=" .. tostring(class) .. " scale=" .. string.format("%.2f", ns.db.scale))
        for _, e in ipairs(ns.BUILTIN[class] or {}) do
            local name, _, id = ns.ResolveSpell(e.spell)
            dprint(("  %s: enabled=%s known=%s spellID=%s"):format(
                e.label, tostring(ns.IsBuiltinEnabled(class, e)), tostring(name ~= nil), tostring(id)))
        end
        for _, t in ipairs(ns.BuildTracked(class, ns.ResolveSpell)) do
            dprint(("  tracked: %s castable=%s auras=%s"):format(t.label, tostring(t.castable), table.concat(t.auras, " / ")))
        end
        dprint(("  cast buttons: castOnKeyPress=%s createError=%s"):format(
            tostring(GetCVar and GetCVar("ActionButtonUseKeyDown")), tostring(ns.castError)))
        for label, s in pairs(ns.slots or {}) do
            dprint(("    %s: panelShown=%s button=%s spell=%s mouse=%s"):format(label, tostring(s:IsShown()),
                tostring(s.cast ~= nil), tostring(s.cast and s.cast:GetAttribute("spell")),
                tostring(s.cast and s.cast:IsMouseEnabled())))
        end
        local have, secret, total, hidden = ns.ReadPlayerBuffs()
        dprint(("  inCombat=%s auras read=%s names hidden by the game=%s -> display %s"):format(
            tostring(UnitAffectingCombat("player")), tostring(total), tostring(hidden),
            secret and "left unchanged (can't tell)" or "updated normally"))
        local names = {}
        for n in pairs(have or {}) do names[#names + 1] = n end
        table.sort(names)
        local shownPanels = 0
        for _, sl in pairs(ns.slots or {}) do if sl:IsShown() then shownPanels = shownPanels + 1 end end
        dprint(("  state: onTaxi=%s deadOrGhost=%s locked=%s panelsShown=%d (warnings are paused on a flight path or when dead)"):format(
            tostring(UnitOnTaxi("player")), tostring(UnitIsDeadOrGhost("player")), tostring(ns.db.locked), shownPanels))
        dprint("  your buffs: " .. (have and table.concat(names, ", ") or "aura API unavailable"))
        ns.db.lastDebug = dbgLines  -- saved on /reload so it can be read from the settings file

    elseif ns.ToggleOptions then
        ns.ToggleOptions()
    end
end
