-- AscendXP_Tweaks: a companion that moves, scales, aligns, recolours and hides AscendXP's text in groups.
-- It works on AscendXP's frames from outside, so AscendXP updates do not overwrite your choices.
-- A group is the texts in one column of the bar or panel (a label and its value), so they move and scale together.
local ADDON, A = ...
-- Saved settings arrive after this file runs; ADDON_LOADED below swaps in the real saved table.
local db = {}

local FRAMES = { "AscendXPBarTracker", "AscendXPTracker" }
local COLUMN_TOLERANCE = 14
local elements, groups = {}, {}
local seen = {}          -- font string -> element
local unlocked, selected = false, nil
local window
local snapBar   -- defined below: holds the bar against the top of the screen

local function say(msg) print("|cff43d9d4AscendXP Tweaks:|r " .. msg) end

-- ===== discovery =====
local function collect(frame, out, visited)
    if not frame or visited[frame] then return end
    visited[frame] = true
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then out[#out + 1] = region end
    end
    for _, child in ipairs({ frame:GetChildren() }) do collect(child, out, visited) end
end

local function snapshotPoints(fs)
    local pts = {}
    for i = 1, fs:GetNumPoints() do
        local p, rel, rp, x, y = fs:GetPoint(i)
        pts[#pts + 1] = { p, rel, rp, x or 0, y or 0 }
    end
    return pts
end

local function conf(g) return db.elements and db.elements[g.key] end

-- Puts every text in the group where the group's settings say (or back as AscendXP made it when unchanged).
local function applyGroup(g)
    local c = conf(g)
    local o = g.members[1].points[1] or { 0, nil, nil, 0, 0 }
    for _, el in ipairs(g.members) do
        local fs = el.fs
        el.applying = true
        fs:ClearAllPoints()
        if not c or A.isDefault(c) then
            for _, p in ipairs(el.points) do fs:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
            fs:SetFont(el.font[1], el.font[2], el.font[3])
            if el.width and el.width > 0 then fs:SetWidth(el.width) end
            fs:SetTextColor(el.color[1], el.color[2], el.color[3])
            fs:SetJustifyH(el.justify)
            fs:SetAlpha(el.alpha)
        else
            for _, p in ipairs(el.points) do
                local gx, gy = A.groupOffset(c, p[4], p[5], o[4], o[5])
                fs:SetPoint(p[1], p[2], p[3], p[4] + gx, p[5] + gy)
            end
            fs:SetFont(el.font[1], A.scaledSize(c, el.font[2]), el.font[3])
            if el.width and el.width > 0 then fs:SetWidth(el.width * (c.scale or 1)) end
            if c.r then fs:SetTextColor(c.r, c.g, c.b) else fs:SetTextColor(el.color[1], el.color[2], el.color[3]) end
            fs:SetJustifyH(c.justify or el.justify)
            fs:SetAlpha(c.hidden and 0 or el.alpha)
        end
        el.applying = false
    end
end

local function buildGroups()
    local items = {}
    for i, el in ipairs(elements) do items[i] = { root = el.root, x = el.left } end
    local idx = A.groupByColumn(items, db.tolerance or COLUMN_TOLERANCE)
    groups = {}
    for n, list in ipairs(idx) do
        local g = { key = elements[list[1]].root .. ":g" .. n, root = elements[list[1]].root, members = {}, n = n }
        for _, i in ipairs(list) do g.members[#g.members + 1] = elements[i]; elements[i].group = g end
        groups[#groups + 1] = g
    end
end

local function discover()
    local added = false
    for _, name in ipairs(FRAMES) do
        local frame = _G[name]
        if frame then
            local list = {}
            collect(frame, list, {})
            for _, fs in ipairs(list) do
                if not seen[fs] then
                    local points = snapshotPoints(fs)
                    local el = { fs = fs, frame = fs:GetParent() or frame, rootFrame = frame, root = name, points = points }
                    el.left = (fs.GetLeft and fs:GetLeft()) or (points[1] and points[1][4]) or 0
                    el.font = { fs:GetFont() }
                    el.width = fs.GetWidth and fs:GetWidth() or 0
                    el.color = { fs:GetTextColor() }
                    el.justify = fs:GetJustifyH() or "LEFT"
                    el.alpha = fs:GetAlpha() or 1
                    if hooksecurefunc then
                        -- AscendXP recolours some text as values change; keep a chosen colour.
                        hooksecurefunc(fs, "SetTextColor", function()
                            local c = el.group and conf(el.group)
                            if not el.applying and c and c.r then
                                el.applying = true
                                fs:SetTextColor(c.r, c.g, c.b)
                                el.applying = false
                            end
                        end)
                    end
                    seen[fs] = el
                    elements[#elements + 1] = el
                    added = true
                end
            end
        end
    end
    if added then
        buildGroups()
        if selected then
            for _, g in ipairs(groups) do if g.key == selected.key then selected = g end end
        end
    end
    for _, g in ipairs(groups) do applyGroup(g) end
end

-- If AscendXP re-anchors a text we moved, take its new anchors as the original and apply our offset again.
local function verify()
    if snapBar then snapBar() end
    for _, g in ipairs(groups) do
        local c = conf(g)
        if c and not A.isDefault(c) and not g.dragging then
            local o = g.members[1].points[1]
            for _, el in ipairs(g.members) do
                if el.fs:GetNumPoints() > 0 and el.points[1] and o then
                    local _, _, _, x, y = el.fs:GetPoint(1)
                    local b = el.points[1]
                    local gx, gy = A.groupOffset(c, b[4], b[5], o[4], o[5])
                    if math.abs((x or 0) - (b[4] + gx)) > 0.01 or math.abs((y or 0) - (b[5] + gy)) > 0.01 then
                        el.points = snapshotPoints(el.fs)
                        applyGroup(g)
                        break
                    end
                end
            end
        end
    end
end

-- ===== window =====
local function label(g)
    local names = {}
    for i, el in ipairs(g.members) do
        if i > 3 then names[#names + 1] = "..." break end
        names[#names + 1] = A.describe(el.fs:GetText())
    end
    return (g.root == "AscendXPBarTracker" and "Bar" or "Panel") .. " group " .. g.n .. ": " .. table.concat(names, " | ")
end

local function refreshWindow()
    if not window then return end
    window.lockBtn:SetText(unlocked and "Lock text" or "Unlock text")
    window.snapBtn:SetText((db.snap and db.snap.on) and ("Snap: on (" .. (db.snap.gap or 0) .. ")") or "Snap to top")
    local g = selected
    if not g then
        window.info:SetText("Click Unlock text, then click a highlighted group on the AscendXP bar or panel. Drag it to move it.")
        return
    end
    local c = conf(g) or {}
    window.info:SetText(label(g) .. "\nOffset " .. (c.dx or 0) .. ", " .. (c.dy or 0) ..
        "   Scale " .. string.format("%.2f", c.scale or 1) .. "x   " .. (c.hidden and "|cffff5050hidden|r" or "shown"))
    if not window.hex:HasFocus() then
        local el = g.members[1]
        window.hex:SetText(c.r and A.toHex(c.r, c.g, c.b) or A.toHex(el.color[1], el.color[2], el.color[3]))
    end
end

-- ===== snap the bar to the top of the screen =====
snapBar = function()
    local bar = _G.AscendXPBarTracker
    local x, y = A.snapOffset(db.snap)
    if not bar or not x then return end
    if bar.IsMovingOrSizing and bar:IsMovingOrSizing() then return end
    local p, _, rp, cx, cy = bar:GetPoint(1)
    if bar:GetNumPoints() == 1 and p == "TOP" and rp == "TOP" and math.abs((cx or 0) - x) < 0.01 and math.abs((cy or 0) - y) < 0.01 then return end
    bar:SetClampedToScreen(false)   -- AscendXP clamps the bar to the screen, which keeps it a little off the edge
    bar:ClearAllPoints()
    bar:SetPoint("TOP", UIParent, "TOP", x, y)
end

local function toggleSnap()
    local bar = _G.AscendXPBarTracker
    db.snap = db.snap or {}
    if db.snap.on then
        A.setSnap(db.snap, false)
        if bar then bar:SetClampedToScreen(true) end
        say("Bar released: drag it freely.")
    else
        if not bar then say("The AscendXP bar is not showing. Switch to bar mode with /axp bar.") return end
        local cx, ux = bar:GetCenter(), UIParent:GetCenter()
        A.setSnap(db.snap, true, (cx and ux) and (cx - ux) or 0)
        say("Bar snapped to the top of the screen. Gap -/+ adjusts it; turn Snap off to drag the bar.")
    end
    snapBar()
    refreshWindow()
end

local function nudgeSnap(delta)
    if db.snap and db.snap.on then
        A.nudgeGap(db.snap, delta)
        snapBar()
        refreshWindow()
    else
        say("Turn Snap to top on first.")
    end
end

local function nudgeSnapX(delta)
    if db.snap and db.snap.on then
        A.nudgeX(db.snap, delta)
        snapBar()
        refreshWindow()
    else
        say("Turn Snap to top on first.")
    end
end

local movers = {}
local function select(g) selected = g; refreshWindow() end

-- The box around every text in the group, laid over the screen so it can be clicked and dragged.
local function placeMover(m, g)
    local l, r, t, b
    for _, el in ipairs(g.members) do
        local fs = el.fs
        if fs.GetLeft and fs:GetLeft() then
            l = math.min(l or fs:GetLeft(), fs:GetLeft()); r = math.max(r or fs:GetRight(), fs:GetRight())
            t = math.max(t or fs:GetTop(), fs:GetTop()); b = math.min(b or fs:GetBottom(), fs:GetBottom())
        end
    end
    if not l then return end
    local root = g.members[1].rootFrame
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", root, "BOTTOMLEFT", l - root:GetLeft(), t - root:GetBottom())
    m:SetSize(math.max(r - l, 16), math.max(t - b, 12))
end

local function makeMover(g)
    local m = CreateFrame("Button", nil, g.members[1].rootFrame)
    m:SetFrameStrata("DIALOG")
    m.bg = m:CreateTexture(nil, "OVERLAY")
    m.bg:SetAllPoints()
    m.bg:SetColorTexture(0.1, 0.8, 0.8, 0.30)
    m:EnableMouse(true)
    m:RegisterForClicks("LeftButtonDown", "RightButtonUp")
    placeMover(m, g)
    m:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        select(g)
        local c = A.cfg(db, g.key)
        local cx, cy = GetCursorPosition()
        local ui = UIParent:GetEffectiveScale()
        g.dragging = { x = cx / ui, y = cy / ui, dx = c.dx, dy = c.dy }
        self:SetScript("OnUpdate", function()
            local d = g.dragging
            if not d then return end
            local nx, ny = GetCursorPosition()
            local ddx, ddy = A.screenToFrame(nx / ui - d.x, ny / ui - d.y, ui, g.members[1].frame:GetEffectiveScale())
            c.dx, c.dy = d.dx + math.floor(ddx + 0.5), d.dy + math.floor(ddy + 0.5)
            applyGroup(g)
            placeMover(self, g)
            refreshWindow()
        end)
    end)
    m:SetScript("OnMouseUp", function(self, button)
        g.dragging = nil
        self:SetScript("OnUpdate", nil)
        if button == "RightButton" then A.reset(db, g.key); applyGroup(g); placeMover(self, g); refreshWindow() end
    end)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(label(g), 1, 0.82, 0)
        GameTooltip:AddLine("Drag to move. Right-click to reset this group.", 1, 1, 1)
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return m
end

local function setUnlocked(on)
    unlocked = on
    for _, m in ipairs(movers) do m:Hide() end
    movers = {}
    if on then
        discover()
        for _, g in ipairs(groups) do
            if g.members[1].fs:IsVisible() then movers[#movers + 1] = makeMover(g) end
        end
    end
    refreshWindow()
end

local function btn(parent, text, w, x, y, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function edit(fn)
    if not selected then say("Select a group first: Unlock text, then click it.") return end
    fn(A.cfg(db, selected.key))
    applyGroup(selected)
    refreshWindow()
end

local function stepSelect(dir)
    if #groups == 0 then return end
    local idx = 0
    for i, g in ipairs(groups) do if g == selected then idx = i end end
    idx = ((idx - 1 + dir) % #groups) + 1
    select(groups[idx])
end

local function resetAll()
    db.elements = {}
    for _, g in ipairs(groups) do applyGroup(g) end
    refreshWindow()
end

local function buildWindow()
    window = CreateFrame("Frame", "AscendXPTweaksWindow", UIParent, "BackdropTemplate")
    window:SetSize(380, 318)
    window:SetPoint("CENTER", 0, -120)
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
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("AscendXP Tweaks")
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    window.info = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    window.info:SetPoint("TOPLEFT", 14, -42)
    window.info:SetWidth(352)
    window.info:SetJustifyH("LEFT")
    window.lockBtn = btn(window, "Unlock text", 110, 14, -92, function() setUnlocked(not unlocked) end)
    btn(window, "< Prev", 70, 134, -92, function() stepSelect(-1) end)
    btn(window, "Next >", 70, 208, -92, function() stepSelect(1) end)
    btn(window, "Left", 70, 14, -124, function() edit(function(c) A.setJustify(c, "LEFT") end) end)
    btn(window, "Centre", 70, 88, -124, function() edit(function(c) A.setJustify(c, "CENTER") end) end)
    btn(window, "Right", 70, 162, -124, function() edit(function(c) A.setJustify(c, "RIGHT") end) end)
    btn(window, "Scale -", 70, 14, -156, function() edit(function(c) A.setScale(c, (c.scale or 1) - 0.1) end) end)
    btn(window, "Scale +", 70, 88, -156, function() edit(function(c) A.setScale(c, (c.scale or 1) + 0.1) end) end)
    btn(window, "Hide / Show", 96, 162, -156, function() edit(function(c) c.hidden = not c.hidden end) end)
    local hexLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hexLabel:SetPoint("TOPLEFT", 14, -192)
    hexLabel:SetText("Colour (RRGGBB):")
    window.hex = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    window.hex:SetSize(70, 20)
    window.hex:SetPoint("TOPLEFT", 130, -188)
    window.hex:SetAutoFocus(false)
    window.hex:SetMaxLetters(7)
    window.hex:SetScript("OnEnterPressed", function(self)
        edit(function(c) if not A.setColor(c, self:GetText()) then say("Colour must be six hex digits, like ff8800.") end end)
        self:ClearFocus()
    end)
    btn(window, "Reset group", 100, 14, -218, function() if selected then A.reset(db, selected.key); applyGroup(selected); refreshWindow() end end)
    btn(window, "Reset all", 90, 122, -218, resetAll)
    window.snapBtn = btn(window, "Snap to top", 120, 14, -250, toggleSnap)
    btn(window, "Gap -", 70, 142, -250, function() nudgeSnap(-A.stepFor(IsShiftKeyDown())) end)
    btn(window, "Gap +", 70, 216, -250, function() nudgeSnap(A.stepFor(IsShiftKeyDown())) end)
    btn(window, "< Bar left", 90, 14, -280, function() nudgeSnapX(-A.stepFor(IsShiftKeyDown())) end)
    btn(window, "Bar right >", 90, 108, -280, function() nudgeSnapX(A.stepFor(IsShiftKeyDown())) end)
    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 206, -285)
    hint:SetText("Shift = 10 px steps")
    window:SetScript("OnHide", function() setUnlocked(false) end)
    window:Hide()
    refreshWindow()
end

local function toggleWindow()
    if not window then buildWindow() end
    if window:IsShown() then window:Hide() else discover(); window:Show(); refreshWindow() end
end

-- ===== startup =====
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then
            AscendXPTweaksDB = AscendXPTweaksDB or {}
            db = AscendXPTweaksDB
        end
        return
    end
    C_Timer.After(2, function() discover(); snapBar() end)
    C_Timer.NewTicker(1, verify)
end)

SLASH_AXPT1 = "/axpt"
SlashCmdList["AXPT"] = function(raw)
    local msg, arg = (raw or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if msg == "reset" then
        resetAll()
        say("All text put back the way AscendXP made it.")
    elseif msg == "top" then
        toggleSnap()
    elseif msg == "info" then
        local bar = _G.AscendXPBarTracker
        if not bar then say("No AscendXP bar frame found (bar mode: /axp bar).") return end
        local p, rel, rp, x, y = bar:GetPoint(1)
        local top, screenTop = bar:GetTop(), UIParent:GetTop()
        local high
        for _, el in ipairs(elements) do
            if el.root == "AscendXPBarTracker" and el.fs.GetTop and el.fs:GetTop() then high = math.max(high or el.fs:GetTop(), el.fs:GetTop()) end
        end
        say(string.format("bar point %s/%s %.1f,%.1f | scale %.2f | frame top %.1f, screen top %.1f | highest text top %s | snap %s gap %s | clamped %s",
            tostring(p), tostring(rp), x or 0, y or 0, bar:GetScale() or 1, top or 0, screenTop or 0,
            high and string.format("%.1f", high) or "?", (db.snap and db.snap.on) and "on" or "off", tostring(db.snap and db.snap.gap or 0),
            tostring(bar:IsClampedToScreen())))
    elseif msg == "group" then
        local n = tonumber(arg)
        if not n or n < 2 or n > 200 then
            say("Texts whose left edges are within this many pixels move together (now " .. (db.tolerance or COLUMN_TOLERANCE) .. "). Use /axpt group 30 to group more, /axpt group 6 to group less. This resets your changes.")
            return
        end
        db.tolerance = n
        db.elements = {}
        for _, g in ipairs(groups) do applyGroup(g) end
        selected = nil
        buildGroups()
        if unlocked then setUnlocked(true) end
        refreshWindow()
        say("Grouping width set to " .. n .. " pixels: " .. #groups .. " groups. Your earlier changes were cleared.")
    else
        toggleWindow()
    end
end

-- exposed for the offline tests
A.discover, A.verify, A.groups = discover, verify, function() return groups end
A.applyGroup, A.setUnlocked, A.getMovers = applyGroup, setUnlocked, function() return movers end
A.snapBar, A.toggleSnap, A.nudgeSnap, A.nudgeSnapX = function() return snapBar() end, toggleSnap, nudgeSnap, nudgeSnapX
A.db = function() return db end
