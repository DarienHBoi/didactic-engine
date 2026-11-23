local ADDON, ns = ...

----------------------------------------------------------------------
-- Display: one movable box holding one of three layouts.
--   list   (A) "Missing buffs (N)" header, collapsible Self/Group/Optional groups,
--              one small line per buff, nested lines for party members missing it
--   strip  (B) a row of icons, thin dividers between groups, badge = others missing it
--   panels     the old big trainer-style panel per buff
-- Every line/icon/panel of a castable buff holds a SecureActionButtonTemplate child
-- (click = cast). The game forbids creating, moving, showing or hiding such frames in
-- combat, so the full layout only runs out of combat (and once more on
-- PLAYER_REGEN_DISABLED, just before lockdown). In combat only text, colour and alpha
-- change: a buff that comes up is dimmed, a buff lost mid-fight is named in the footer.
----------------------------------------------------------------------
local box, handle
local cells = {}           -- id -> frame (or texture for dividers)
ns.cells = cells
local laidOut = {}         -- ids placed by the last full layout
local PAD = 6
local FONT = "Fonts\\FRIZQT__.TTF"

ns.HEADER_COLORS = {
    { id = "gold",  name = "Gold",  rgb = { 1, 0.82, 0 } },
    { id = "white", name = "White", rgb = { 1, 1, 1 } },
    { id = "blue",  name = "Blue",  rgb = { 0.45, 0.75, 1 } },
    { id = "green", name = "Green", rgb = { 0.45, 1, 0.45 } },
}
local function headerRGB()
    for _, c in ipairs(ns.HEADER_COLORS) do
        if c.id == ns.db.headerColor then return unpack(c.rgb) end
    end
    return 1, 0.82, 0
end

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
ns.clamp = clamp

local function fontPath()
    if GameFontNormal and GameFontNormal.GetFont then
        local p = GameFontNormal:GetFont()
        if p then return p end
    end
    return FONT
end

local function setFont(fs, size)
    fs:SetFont(fontPath(), size, "")
end

----------------------------------------------------------------------
-- Position and scale (x,y = screen position of the box's anchored corner:
-- top-right when growing down, bottom-right when growing up)
----------------------------------------------------------------------
local function corner() return ns.db.growUp and "BOTTOMRIGHT" or "TOPRIGHT" end

function ns.ApplyPosition()
    if InCombatLockdown() then ns.posDirty = true; return end
    ns.posDirty = false
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
        box:SetPoint(corner(), UIParent, "BOTTOMLEFT", x / sc, y / sc)
    else
        box:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
end

function ns.SavePosition()
    local sc = box:GetScale()
    local r = box:GetRight()
    local v = ns.db.growUp and box:GetBottom() or box:GetTop()
    if r and v then ns.db.x, ns.db.y = r * sc, v * sc end
end

function ns.SetScaleKeepCorner(sc)
    if InCombatLockdown() then ns.db.scale = sc; ns.posDirty = true; return end
    if ns.db.x == nil then ns.SavePosition() end
    ns.db.scale = sc
    ns.ApplyPosition()
    if ns.OnScaleChanged then ns.OnScaleChanged(sc) end
end

function ns.ResetLayout()
    if InCombatLockdown() then print("|cffffd200MBW|r can't move the display in combat."); return end
    ns.db.scale, ns.db.x, ns.db.y = 1, nil, nil
    ns.ApplyPosition()
end

-- Change one setting from the options panel or a slash command. Layout work that the game
-- forbids in combat waits for the end of combat (PLAYER_REGEN_ENABLED refreshes).
function ns.SetOption(k, v)
    ns.db[k] = v
    if k == "growUp" then
        ns.SavePosition()          -- re-express the position from the other corner
        ns.ApplyPosition()
    elseif k == "scale" then
        ns.SetScaleKeepCorner(v)
    end
    ns.Refresh()
end

-- Shift-drag to move, shift-scroll to scale (any time it is shown; not in combat).
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

----------------------------------------------------------------------
-- Tooltip (strip icons; also on list lines)
----------------------------------------------------------------------
local function showTip(owner)
    local it = owner.item or (owner:GetParent() and owner:GetParent().item)
    if not (it and GameTooltip) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(it.label, 1, 0.82, 0)
    if it.playerMissing then GameTooltip:AddLine("Missing on you", 1, 0.3, 0.3) end
    for _, w in ipairs(it.who or {}) do GameTooltip:AddLine("Missing on " .. w.name, 1, 0.6, 0.6) end
    if it.total then GameTooltip:AddLine(("%d of %d have it"):format(it.have, it.total), 0.8, 0.8, 0.8) end
    if it.passive then GameTooltip:AddLine("Passive: can't be cast", 0.6, 0.6, 0.6)
    elseif owner.cast or owner._isCast then GameTooltip:AddLine("Click to cast", 0.5, 1, 0.5) end
    GameTooltip:Show()
end
local function hideTip() if GameTooltip then GameTooltip:Hide() end end

----------------------------------------------------------------------
-- Click-to-cast: a transparent secure button covering a cell. Created and changed only
-- out of combat; a buff that first appears in combat gets its button after combat.
----------------------------------------------------------------------
local function castUnit(it, unit)
    if unit then return unit end
    if it.playerMissing or #(it.who or {}) == 0 then return "player" end
    return it.who[1].unit                     -- you have it: cast on the first one missing it
end

local function attachCast(c, it, unit)
    if InCombatLockdown() then return end
    if not it.castable then
        if c.cast then c.cast:Hide() end
        return
    end
    if not c.cast then
        local ok, btn = pcall(CreateFrame, "Button", nil, c, "SecureActionButtonTemplate")
        if not (ok and btn) then ns.castError = tostring(btn); return end
        btn:SetAllPoints(c)
        btn:SetFrameLevel(c:GetFrameLevel() + 5)
        -- both: the game picks key-down or key-up from the "cast on key press" setting
        btn:RegisterForClicks("AnyUp", "AnyDown")
        makeMovable(btn)
        btn._isCast = true
        btn:SetScript("OnEnter", showTip)
        btn:SetScript("OnLeave", hideTip)
        btn:SetAttribute("type", "spell")
        c.cast = btn
    end
    local u = castUnit(it, unit)
    if c.cast:GetAttribute("spell") ~= it.label then c.cast:SetAttribute("spell", it.label) end  -- by name: highest rank
    if c.cast:GetAttribute("unit") ~= u then c.cast:SetAttribute("unit", u) end
    c.cast:Show()
    -- while unlocked the box must be draggable, so the cast button lets the mouse through
    c.cast:EnableMouse(ns.db.locked and true or false)
end

----------------------------------------------------------------------
-- Cell factories
----------------------------------------------------------------------
local function base(id, layout, kind)
    local c = CreateFrame(kind or "Frame", nil, box)
    c.id, c.layout = id, layout
    c:EnableMouse(true)
    makeMovable(c)
    c:SetScript("OnEnter", showTip)
    c:SetScript("OnLeave", hideTip)
    cells[id] = c
    return c
end

local function iconWithEdge(c)
    c.edge = c:CreateTexture(nil, "BACKGROUND")
    c.edge:SetColorTexture(0.9, 0.1, 0.1, 0.95)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.edge:SetPoint("TOPLEFT", c.icon, "TOPLEFT", -1, 1)
    c.edge:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", 1, -1)
end

local function header(id)
    local c = cells[id]
    if c then return c end
    c = base(id, "list", "Button")
    c:SetScript("OnEnter", nil)
    c:SetScript("OnLeave", nil)
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.label:SetPoint("LEFT", c, "LEFT", 0, 0)
    c.label:SetJustifyH("LEFT")
    if c.SetFontString then c:SetFontString(c.label) end
    c:RegisterForClicks("LeftButtonUp")
    c:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            print("|cffffd200MBW|r collapse/expand works out of combat.")
            return
        end
        local k = self.group or "ALL"
        ns.db.collapsed[k] = not ns.db.collapsed[k]
        ns.Refresh()
    end)
    return c
end

local function listRow(id)
    local c = cells[id]
    if c then return c end
    c = base(id, "list")
    iconWithEdge(c)
    c.name = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(false)
    c.count = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.count:SetJustifyH("RIGHT")
    return c
end

local function whoRow(id)
    local c = cells[id]
    if c then return c end
    c = base(id, "list")
    c.name = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.name:SetJustifyH("LEFT")
    c.name:SetTextColor(1, 0.55, 0.55)
    return c
end

local function stripIcon(id)
    local c = cells[id]
    if c then return c end
    c = base(id, "strip")
    iconWithEdge(c)
    c.badge = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.badge:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 2, -2)
    c.badge:SetTextColor(1, 1, 1)
    return c
end

local function divider(id)
    local d = cells[id]
    if d then return d end
    d = box:CreateTexture(nil, "ARTWORK")
    d:SetColorTexture(1, 0.82, 0, 0.5)
    d.id, d.layout = id, "strip"
    cells[id] = d
    return d
end

-- old big panel (third layout)
local SLOT, PANEL_H, ICON = 300, 110, 72
local GAP = SLOT + 14
local function bigPanel(id)
    local s = cells[id]
    if s then return s end
    s = CreateFrame("Frame", nil, box, "BackdropTemplate")
    s.id, s.layout = id, "panels"
    cells[id] = s
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
    s.markBox = CreateFrame("Frame", nil, s, "BackdropTemplate")
    s.markBox:SetSize(ICON + 10, ICON + 10)
    s.markBox:SetPoint("LEFT", s, "LEFT", 16, 0)
    s.markBox:SetBackdrop({ edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 14 })
    s.markBox:SetBackdropBorderColor(0.7, 0.55, 0.3, 1)
    s.mark = s:CreateTexture(nil, "ARTWORK")
    s.mark:SetSize(ICON, ICON)
    s.mark:SetPoint("CENTER", s.markBox, "CENTER", 0, 0)
    s.mark:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    s.text = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    s.text:SetPoint("TOPLEFT", s, "TOPLEFT", ICON + 40, -24)
    s.text:SetJustifyH("LEFT")
    s.text:SetTextColor(1, 0.82, 0)
    s.text:SetWordWrap(false)
    s.text:SetWidth(SLOT - ICON - 56)
    s.body = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
    return s
end

----------------------------------------------------------------------
-- Layouts (out of combat only). Each returns the box size and fills `place`.
----------------------------------------------------------------------
local function setIcon(c, it, size)
    c.icon:SetTexture(it.icon)
    c.icon:SetSize(size, size)
    c.edge:SetShown(ns.db.redEdge and true or false)
end

-- vertical stacking: entries {cell, h, x} top to bottom; anchored from the top (grow down)
-- or from the bottom (grow up) so the box grows away from its fixed corner
local function stack(entries, width, height)
    local up = ns.db.growUp
    local y = PAD
    for _, e in ipairs(entries) do
        local c = e.cell
        c:ClearAllPoints()
        if up then
            c:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", PAD + e.x, height - y - e.h)
        else
            c:SetPoint("TOPLEFT", box, "TOPLEFT", PAD + e.x, -y)
        end
        c:SetSize(width - PAD * 2 - e.x, e.h)
        y = y + e.h + ns.db.spacing
    end
end

local function layoutList(view)
    local db = ns.db
    local fs, isz, sp = db.fontSize, db.iconSize, db.spacing
    local lineH = math.max(isz, fs + 2)
    local hr, hg, hb = headerRGB()
    local entries, width = {}, 150
    local function add(c, h, x, textW)
        entries[#entries + 1] = { cell = c, h = h, x = x }
        width = math.max(width, x + textW + PAD * 2 + 8)
        laidOut[c.id] = true
        c:Show()
    end

    local hdr = header("hdr")
    hdr.item = nil
    setFont(hdr.label, fs + 1)
    hdr.label:SetTextColor(hr, hg, hb)
    local t = ("Missing buffs (%d)"):format(view.count)
    hdr:SetText(t); hdr.label:SetText(t)
    add(hdr, fs + 6, 0, hdr.label:GetStringWidth())
    if not db.collapsed.ALL then
        for _, g in ipairs(view.groups) do
            local gh = header("grp:" .. g.id)
            gh.group = g.id
            setFont(gh.label, fs)
            gh.label:SetTextColor(hr, hg, hb)
            local open = not db.collapsed[g.id]
            local gt = (open and "- " or "+ ") .. g.name .. " (" .. #g.items .. ")"
            gh:SetText(gt); gh.label:SetText(gt)
            add(gh, fs + 4, 4, gh.label:GetStringWidth())
            if open then
                for _, it in ipairs(g.items) do
                    local r = listRow("row:" .. it.key)
                    r.item = it
                    setIcon(r, it, isz)
                    r.icon:ClearAllPoints()
                    r.icon:SetPoint("LEFT", r, "LEFT", 1, 0)
                    setFont(r.name, fs)
                    r.name:SetText(it.label)
                    r.name:SetTextColor(it.playerMissing and 1 or 0.85, it.playerMissing and 1 or 0.85,
                        it.playerMissing and 1 or 0.85)
                    r.name:ClearAllPoints()
                    r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
                    setFont(r.count, fs)
                    r.count:SetText(it.total and (it.have .. "/" .. it.total) or "")
                    r.count:ClearAllPoints()
                    r.count:SetPoint("RIGHT", r, "RIGHT", -2, 0)
                    r:SetAlpha(1)
                    attachCast(r, it)
                    add(r, lineH, 12, isz + 5 + r.name:GetStringWidth() + 8 + r.count:GetStringWidth())
                    for _, w in ipairs(it.who) do
                        local wr = whoRow("who:" .. it.key .. ":" .. w.unit)
                        wr.item = it
                        setFont(wr.name, math.max(8, fs - 1))
                        wr.name:SetText(w.name)
                        wr.name:ClearAllPoints()
                        wr.name:SetPoint("LEFT", wr, "LEFT", 0, 0)
                        wr:SetAlpha(1)
                        attachCast(wr, it, w.unit)
                        add(wr, fs + 2, 12 + isz + 5, wr.name:GetStringWidth())
                    end
                end
            end
        end
    end
    local height = PAD * 2
    for i, e in ipairs(entries) do height = height + e.h + (i > 1 and sp or 0) end
    stack(entries, width, height)
    return width, height
end

local function layoutStrip(view)
    local db = ns.db
    local size = db.iconSize + 8                -- strip icons a bit bigger than list icons
    local sp = math.max(2, db.spacing)
    local x, n = PAD, 0
    for gi, g in ipairs(view.groups) do
        if gi > 1 then
            n = n + 1
            local d = divider("div:" .. n)
            d:ClearAllPoints()
            d:SetPoint("TOPLEFT", box, "TOPLEFT", x + 2, -PAD)
            d:SetSize(1, size)
            d:Show()
            laidOut[d.id] = true
            x = x + 5 + sp
        end
        for _, it in ipairs(g.items) do
            local c = stripIcon("ico:" .. it.key)
            c.item = it
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", box, "TOPLEFT", x, -PAD)
            c:SetSize(size, size)
            setIcon(c, it, size)
            c.icon:ClearAllPoints()
            c.icon:SetPoint("CENTER", c, "CENTER", 0, 0)
            c.icon:SetAlpha(g.id == "OPTIONAL" and 0.45 or 1)
            setFont(c.badge, math.max(8, db.fontSize - 1))
            local others = #it.who
            c.badge:SetText(others > 0 and tostring(others) or "")
            c.badge:SetShown(others > 0)
            c:SetAlpha(1)
            c:Show()
            attachCast(c, it)
            laidOut[c.id] = true
            x = x + size + sp
        end
    end
    return math.max(x - sp + PAD, size + PAD * 2), size + PAD * 2
end

local function layoutPanels(view)
    local list = {}
    for _, g in ipairs(view.groups) do
        for _, it in ipairs(g.items) do list[#list + 1] = it end
    end
    local n = #list
    for i, it in ipairs(list) do
        local s = bigPanel("pan:" .. it.key)
        s.item = it
        s.mark:SetTexture(it.icon)
        s.text:SetText(it.label)
        attachCast(s, it)
        local who = {}
        for _, w in ipairs(it.who) do who[#who + 1] = w.name end
        local first = it.playerMissing and ("Your " .. it.label .. " is missing.")
            or ("Missing on: " .. table.concat(who, ", "))
        s.body:SetText(first .. "\n"
            .. (it.passive and "It is a passive effect: it cannot be cast."
                or ((s.cast and s.cast:IsShown()) and "Click here to cast it." or "Cast it to dismiss this warning.")))
        s:ClearAllPoints()
        s:SetPoint("CENTER", box, "CENTER", (i - (n + 1) / 2) * GAP, 0)
        s:SetAlpha(1)
        s:Show()
        if not s.ag:IsPlaying() then s.ag:Play() end
        laidOut[s.id] = true
    end
    return SLOT, PANEL_H
end

local LAYOUTS = { list = layoutList, strip = layoutStrip, panels = layoutPanels }

local function applyLook()
    local db = ns.db
    local unlocked = not db.locked
    local panels = db.layout == "panels"
    box.bg:SetShown((db.showBg and not panels) or unlocked)
    box.bg:SetAlpha(unlocked and 0.45 or db.bgAlpha)
    box.border:SetShown(db.showBorder and not panels and true or false)
    box.hint:SetShown(unlocked)
end

local function fullLayout(view, vis)
    if ns.posDirty then ns.ApplyPosition() end
    local old = laidOut
    laidOut = {}
    local w, h = 0, 0
    if vis ~= "hide" then
        w, h = (LAYOUTS[ns.db.layout] or layoutList)(view)
    end
    for id in pairs(old) do
        if not laidOut[id] then
            local c = cells[id]
            if c.ag then c.ag:Stop() end
            c:Hide()
        end
    end
    box:SetSize(math.max(w, 1), math.max(h, 1))
    applyLook()
    box.footer:SetText("")
    box.footer:ClearAllPoints()
    if ns.db.growUp then box.footer:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", 0, 2)
    else box.footer:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2) end
    -- "hide" keeps the box itself shown (invisible, empty, no mouse): a frame holding
    -- click-to-cast buttons can't be shown again in combat, but its footer text can.
    local hardHide = ns.db.locked and (ns.enteringCombat and not ns.db.showInCombat
        or (ns.db.onlyInGroup and not (IsInGroup and IsInGroup()))
        or UnitIsDeadOrGhost("player") or UnitOnTaxi("player"))
    if hardHide then box:Hide() else box:Show() end
    if vis == "hide" then
        box.bg:Hide(); box.border:Hide()
        box:SetAlpha(1)
    else
        box:SetAlpha(vis == "fade" and 0.3 or 1)
    end
end

-- In combat: nothing protected moves; only text, colour and alpha change.
local function combatUpdate(view, vis)
    local byKey, whoSet = {}, {}
    for _, g in ipairs(view.groups) do
        for _, it in ipairs(g.items) do
            byKey[it.key] = it
            for _, w in ipairs(it.who) do whoSet[it.key .. ":" .. w.unit] = true end
        end
    end
    local onScreen = {}
    for id in pairs(laidOut) do
        local c = cells[id]
        local kind, rest = id:match("^(%a+):(.+)$")
        if kind == "row" or kind == "ico" or kind == "pan" then
            local it = byKey[rest]
            if it then onScreen[rest] = true end
            c:SetAlpha(it and 1 or 0.3)
            if c.name then c.name:SetTextColor(it and 1 or 0.5, it and 1 or 0.5, it and 1 or 0.5) end
        elseif kind == "who" then
            c:SetAlpha(whoSet[rest] and 1 or 0.3)
        end
    end
    if cells.hdr and laidOut.hdr then
        local t = ("Missing buffs (%d)"):format(view.count)
        cells.hdr:SetText(t); cells.hdr.label:SetText(t)
    end
    local extra = {}
    for key, it in pairs(byKey) do
        if not onScreen[key] and it.playerMissing then extra[#extra + 1] = it.label end
    end
    table.sort(extra)
    box.footer:SetText(#extra > 0 and ("Also missing: " .. table.concat(extra, ", ")) or "")
    if vis == "hide" and #extra == 0 then
        box:SetAlpha(next(laidOut) and 0 or 1)   -- empty box: footer only
    elseif vis == "fade" then
        box:SetAlpha(0.3)
    else
        box:SetAlpha(1)
    end
    if #extra > 0 then box:SetAlpha(1) end
end

function ns.Render(view, vis)
    if InCombatLockdown() then
        combatUpdate(view, vis)
    else
        fullLayout(view, vis)
    end
end

function ns.SetLocked(locked)
    ns.db.locked = locked and true or false
    if not InCombatLockdown() then
        box:EnableMouse(not ns.db.locked)
        handle:SetShown(not ns.db.locked)
    end
    ns.Refresh()
end

----------------------------------------------------------------------
-- The box
----------------------------------------------------------------------
function ns.BuildDisplay()
    box = CreateFrame("Frame", "MissingBuffWarningFrame", UIParent)
    ns.box = box
    box:SetSize(160, 40)
    box:SetFrameStrata("HIGH")
    box:SetClampedToScreen(true)
    box:SetMovable(true)
    box:RegisterForDrag("LeftButton")

    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bg:SetColorTexture(0, 0, 0, 1)
    box.border = CreateFrame("Frame", nil, box, "BackdropTemplate")
    box.border:SetPoint("TOPLEFT", box, "TOPLEFT", -3, 3)
    box.border:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 3, -3)
    if box.border.SetBackdrop then
        box.border:SetBackdrop({ edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 12 })
        box.border:SetBackdropBorderColor(0.55, 0.43, 0.28, 1)
    end
    box.border:EnableMouse(false)
    box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.hint:SetPoint("BOTTOM", box, "TOP", 0, 4)
    box.hint:SetText("Drag to move - drag corner to resize")
    box.footer = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box.footer:SetTextColor(1, 0.3, 0.3)
    box.footer:SetJustifyH("RIGHT")

    box:SetScript("OnDragStart", function(self)
        if not ns.db.locked and not InCombatLockdown() then self:StartMoving() end
    end)
    box:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.SavePosition()
        ns.ApplyPosition()
    end)

    -- bottom-left resize handle, scales live; the anchored corner stays put
    handle = CreateFrame("Button", nil, box)
    handle:SetSize(16, 16)
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
        if InCombatLockdown() then return end
        if ns.db.x == nil then ns.SavePosition() end
        local es = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        local sx, sy = cx / es, cy / es
        local s0 = box:GetScale()
        local w0 = math.max(box:GetWidth(), 40)
        self:SetScript("OnUpdate", function()
            if InCombatLockdown() then self:SetScript("OnUpdate", nil); return end
            local mx, my = GetCursorPosition()
            mx, my = mx / es, my / es
            local d = ((sx - mx) + (sy - my)) / 2 -- left/down = bigger
            ns.db.scale = clamp((w0 * s0 + d) / w0, 0.4, 4)
            ns.ApplyPosition()
            if ns.OnScaleChanged then ns.OnScaleChanged(ns.db.scale) end
        end)
    end)
    handle:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    handle:Hide()

    -- holding shift shows the resize handle on a live display
    local mod = CreateFrame("Frame")
    mod:RegisterEvent("MODIFIER_STATE_CHANGED")
    mod:SetScript("OnEvent", function()
        if ns.db and ns.db.locked and not InCombatLockdown() then
            handle:SetShown(IsShiftKeyDown() and next(laidOut) ~= nil)
        end
    end)
end
