-- Board window, "Fairground tent" look: red/cream striped header with a plate, a strength tower (pole, bell, gradient fill up to the
-- record, marker, scale labels), the champion card, the newest records as rows, ticket tabs. History tab = the same rows, scrolling.
-- Options keep their controls, in the same palette. The frame is created lazily on the first toggle. No OnUpdate anywhere in this file.
local addonName, RB = ...
local L = RB.L

local Board = {}
RB.Board = Board

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Bell art: our own 64 px Media/Bell.tga (made by rtb/make_bell_tga.py). INV_Misc_Bell_01 is not a bell on this client.
local BELL_FILE = "Interface\\AddOns\\RingTheBell\\Media\\Bell"
local DOT = "\194\183"

local INK, GOLD, GOLD2 = { 0.1, 0.05, 0.13 }, { 1, 0.82, 0.29 }, { 0.78, 0.59, 0.16 }
local RED, CREAM, BROWN = { 0.7, 0.15, 0.17 }, { 0.96, 0.9, 0.77 }, { 0.35, 0.17, 0.04 }
local GREY = { 0.73, 0.73, 0.67 }
local FRAME_W, FRAME_H = 520, 380
local TENT_H = 46
local POLE_H = 240
local ROW_H, HIST_MAX, BOARD_ROWS = 24, 50, 5
Board.POLE_H, Board.ROW_H = POLE_H, ROW_H

local frame, pages, ui = nil, {}, {}
local pushEnabled = true

-- helpers ------------------------------------------------------------------------------------------------------------
local function commas(n)
    if type(n) ~= "number" then return tostring(n) end
    local s = string.format("%d", math.floor(n + 0.5))
    local sign, digits = s:match("^(-?)(%d+)$")
    if not digits then return s end
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return sign .. (digits:gsub("^,", ""))
end

local function short(name)
    if type(name) ~= "string" then return "?" end
    return name:match("^([^%-]+)") or name
end

local function when(t)
    if type(t) ~= "number" or type(date) ~= "function" then return "" end
    local ok, s = pcall(date, "%d %b %H:%M", t)
    return (ok and type(s) == "string") and s or ""
end

-- smallest 1/2/2.5/5 x 10^k strictly above the amount; an empty board uses 1000
function Board.niceScale(amount)
    if type(amount) ~= "number" or amount <= 0 then return 1000 end
    local p = 1
    while p * 10 <= amount do p = p * 10 end
    while p > 1 and p > amount do p = p / 10 end
    for _, m in ipairs({ 1, 2, 2.5, 5, 10 }) do
        if p * m > amount then return p * m end
    end
    return p * 10
end

-- 2500 -> "2.5k", 1250 -> "1.25k", 1000 -> "1k", 500 -> "500"
function Board.kfmt(n)
    if type(n) ~= "number" then return "?" end
    if n >= 1000000 then
        return (string.format("%.2f", n / 1000000):gsub("0+$", ""):gsub("%.$", "")) .. "M"
    end
    if n >= 1000 then
        local s = string.format("%.2f", n / 1000):gsub("0+$", ""):gsub("%.$", "")
        return s .. "k"
    end
    return string.format("%d", math.floor(n + 0.5))
end

function Board.bellIcon() return BELL_FILE end

-- plain texture of a spell, or the question mark
function Board.spellIcon(spellID)
    if type(spellID) ~= "number" then return QUESTION end
    local ok, tex = pcall(function() return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID) end)
    if ok and not (L.isSecret and L.isSecret(tex)) and tex and (type(tex) == "number" or (type(tex) == "string" and tex ~= "")) then return tex end
    return QUESTION
end

local function rect(parent, layer, c, w, h)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(WHITE)
    t:SetVertexColor(c[1], c[2], c[3], 1)
    if w and h then t:SetSize(w, h) elseif w then t:SetWidth(w) elseif h then t:SetHeight(h) end
    return t
end

-- vertical gradient (bottom colour a -> top colour b); keeps the flat fallback colour if no gradient API works
local function gradient(t, orient, a, b)
    t:SetVertexColor(a[1], a[2], a[3], 1)  -- fallback colour; a working gradient overrides it, so never reset it afterwards
    local done = false
    if type(CreateColor) == "function" then
        done = pcall(function() t:SetGradient(orient, CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1)) end)
    end
    if not done then done = pcall(t.SetGradient, t, orient, a[1], a[2], a[3], b[1], b[2], b[3]) end
    if not done then pcall(t.SetGradientAlpha, t, orient, a[1], a[2], a[3], 1, b[1], b[2], b[3], 1) end
end

-- a 1..bw px border of four rects around a frame (drawn on BORDER, inside the frame)
local function border(parent, c, bw)
    local function edge(p1, p2, w, h)
        local t = rect(parent, "BORDER", c, w, h)
        t:SetPoint(p1, parent, p1, 0, 0)
        if p2 then t:SetPoint(p2, parent, p2, 0, 0) end
        return t
    end
    edge("TOPLEFT", "TOPRIGHT", nil, bw):SetHeight(bw)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, bw):SetHeight(bw)
    edge("TOPLEFT", "BOTTOMLEFT", bw, nil):SetWidth(bw)
    edge("TOPRIGHT", "BOTTOMRIGHT", bw, nil):SetWidth(bw)
end

-- text with an explicit font size (pcall); falls back to a stock font object when the font call is refused
local function label(parent, size, point, rel, relPoint, x, y, c, flags, w)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local ok = pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, flags or "")
    if not ok then
        ok = pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", size or 12, flags or "")
        if not ok and GameFontNormal then pcall(fs.SetFontObject, fs, GameFontNormal) end
    end
    fs:SetPoint(point, rel, relPoint or point, x or 0, y or 0)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(w or 200)  -- explicit width; callers narrow it
    pcall(fs.SetWordWrap, fs, false)  -- one line only: the client truncates instead of wrapping
    if fs.SetMaxLines then pcall(fs.SetMaxLines, fs, 1) end
    c = c or CREAM
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

-- cream ticket button
local function button(parent, text, w, point, rel, relPoint, x, y)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 22)
    b:SetPoint(point, rel, relPoint or point, x or 0, y or 0)
    b.bg = rect(b, "BACKGROUND", CREAM); b.bg:SetAllPoints(b)
    border(b, { 0.54, 0.29, 0.09 }, 1)
    local fs = label(b, 12, "CENTER", b, "CENTER", 0, 0, BROWN, nil, w - 6)
    fs:SetJustifyH("CENTER")
    pcall(b.SetFontString, b, fs)
    b.fs = fs
    b:SetText(text)
    pcall(b.SetHighlightTexture, b, WHITE, "ADD")
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl and hl.SetVertexColor then pcall(hl.SetVertexColor, hl, 1, 1, 1, 0.25) end
    return b
end

local function options() return RB.db and RB.db.options end

-- a record row: small icon, class-coloured name, spell, date, amount right-aligned in gold
local function makeRow(parent, y, w)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(w, ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20); row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    pcall(row.icon.SetTexCoord, row.icon, 0.08, 0.92, 0.08, 0.92)
    row.name = label(row, 13, "LEFT", row, "LEFT", 30, 0)
    row.name:SetWidth(84)
    row.spell = label(row, 12, "LEFT", row, "LEFT", 118, 0, GREY)
    row.spell:SetWidth(math.max(60, w - 118 - 164))
    row.date = label(row, 11, "RIGHT", row, "RIGHT", -82, 0, GREY)
    row.date:SetWidth(80); row.date:SetJustifyH("RIGHT")
    row.amount = label(row, 13, "RIGHT", row, "RIGHT", -4, 0, GOLD, "OUTLINE")
    row.amount:SetWidth(76); row.amount:SetJustifyH("RIGHT")
    local line = rect(row, "BORDER", { 1, 1, 1 }, nil, 1)
    line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0); line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    line:SetVertexColor(1, 1, 1, 0.07)
    row:Hide()
    return row
end

local function fillRow(row, h, rank)
    if not h then row:Hide(); return end
    row.icon:SetTexture(Board.spellIcon(h.spellID))
    row.name:SetText((rank and (rank .. ". ") or "") .. short(h.player))
    row.name:SetTextColor(L.classColor(h.class))
    row.spell:SetText(tostring(h.spell or "?") .. " " .. DOT .. " on " .. tostring(h.target or "?"))
    row.date:SetText(when(h.t))
    row.amount:SetText(commas(h.amount))
    row:Show()
end

-- refresh ------------------------------------------------------------------------------------------------------------
local function refreshBoard()
    local rec = RB.db and RB.db.record
    local amount = rec and rec.amount
    local scale = Board.niceScale(amount)
    local h = 0
    if type(amount) == "number" and amount > 0 then h = math.max(1, math.floor(POLE_H * amount / scale)) end
    ui.fill:SetHeight(h)
    ui.fill:SetShown(h > 0)
    ui.marker:SetShown(h > 0)
    ui.marker:ClearAllPoints()
    ui.marker:SetPoint("BOTTOM", ui.pole, "BOTTOM", 0, h)
    ui.scaleTop:SetText(Board.kfmt(scale))
    ui.scaleMid:SetText(Board.kfmt(scale / 2))
    if rec then
        ui.hint:Hide(); ui.hint2:Hide()
        ui.cardLabel:Show(); ui.champIcon:Show(); ui.champFrame:Show(); ui.glow:Show()
        ui.champIcon:SetTexture(Board.spellIcon(rec.spellID))
        ui.name:SetText(short(rec.player)); ui.name:SetTextColor(L.classColor(rec.class)); ui.name:Show()
        ui.amount:SetText(commas(rec.amount)); ui.amount:Show()
        local parts = { tostring(rec.spell or "?"), "on " .. tostring(rec.target or "?") }
        local d = when(rec.t)
        if d ~= "" then parts[#parts + 1] = d end
        ui.meta:SetText(table.concat(parts, " " .. DOT .. " ")); ui.meta:Show()
    else
        ui.name:Hide(); ui.amount:Hide(); ui.meta:Hide(); ui.cardLabel:Hide(); ui.champIcon:Hide(); ui.champFrame:Hide(); ui.glow:Hide()
        ui.hint:SetText("Nobody has rung the bell yet"); ui.hint:Show()
        ui.hint2:SetText("Go hit something!"); ui.hint2:Show()
    end
    local lb = RB.db and L.leaderboard(RB.db) or {}
    for i = 1, BOARD_ROWS do fillRow(ui.boardRows[i], lb[i], i) end
    ui.recentLabel:SetShown(#lb > 0)
end

local function refreshHistory()
    local hist = (RB.db and RB.db.history) or {}
    for i = 1, HIST_MAX do fillRow(ui.histRows[i], hist[i]) end
    ui.histEmpty:SetShown(#hist == 0)
    ui.histChild:SetHeight(math.max(1, math.min(#hist, HIST_MAX)) * ROW_H)
end

local function refreshOptions()
    local o = options() or {}
    ui.sound:SetChecked(o.sound ~= false)
    ui.popup:SetChecked(o.popup ~= false)
    ui.pip:SetChecked(o.pip ~= false)
end

function Board.refresh()
    if not frame or not frame:IsShown() then return end
    refreshBoard(); refreshHistory(); refreshOptions()
end

-- actions ------------------------------------------------------------------------------------------------------------
local function resetPopup()
    if not RB.db then return end
    RB.db.popup = {}
    local b = RingTheBellBanner
    if b and b.ClearAllPoints then
        b:ClearAllPoints()
        b:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

local function clearLocal()
    if not RB.db then return end
    RB.db.record = nil
    RB.db.history = {}
    RB.db.best = {}
    Board.refresh()
end

-- Task 8 can disable the Push update button before or after the window exists.
function Board.setPushEnabled(on)
    pushEnabled = on and true or false
    local b = Board.pushButton
    if b then
        if pushEnabled then b:Enable() else b:Disable() end
        b:SetAlpha(pushEnabled and 1 or 0.5)
    end
end

-- build --------------------------------------------------------------------------------------------------------------
local function checkbox(parent, text, y, key)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    label(parent, 13, "LEFT", cb, "RIGHT", 4, 0, GOLD, nil, 200):SetText(text)
    cb:SetScript("OnClick", function(self)
        local o = options()
        if not o then return end
        o[key] = self:GetChecked() and true or false
        if key == "pip" and RB.Pip and RB.Pip.refresh then RB.Pip.refresh() end
    end)
    return cb
end

local function showTab(name)
    for k, p in pairs(pages) do p:SetShown(k == name) end
    for k, b in pairs(ui.tabs) do
        local c = (k == name) and GOLD or CREAM
        b.bg:SetVertexColor(c[1], c[2], c[3], 1)
    end
    ui.current = name
end

local function buildTent(f)
    local tent = CreateFrame("Frame", nil, f)
    tent:SetHeight(TENT_H)
    tent:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3); tent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    tent:SetSize(FRAME_W - 6, TENT_H)
    local x, i = 0, 0
    while x < FRAME_W - 6 do
        local w = math.min(30, FRAME_W - 6 - x)
        local s = rect(tent, "BACKGROUND", (i % 2 == 0) and RED or CREAM, w, TENT_H)
        s:SetPoint("TOPLEFT", tent, "TOPLEFT", x, 0)
        x, i = x + 30, i + 1
    end
    local rule = rect(tent, "BORDER", GOLD2, nil, 3)
    rule:SetPoint("BOTTOMLEFT", tent, "BOTTOMLEFT", 0, 0); rule:SetPoint("BOTTOMRIGHT", tent, "BOTTOMRIGHT", 0, 0)
    local plate = CreateFrame("Frame", nil, tent)
    plate:SetSize(220, 30); plate:SetPoint("CENTER", tent, "CENTER", 0, 1)
    local pbg = rect(plate, "BACKGROUND", INK); pbg:SetAllPoints(plate)
    border(plate, GOLD2, 2)
    local pbell = plate:CreateTexture(nil, "ARTWORK")
    pbell:SetSize(18, 18); pbell:SetPoint("LEFT", plate, "LEFT", 10, 0); pbell:SetTexture(Board.bellIcon())
    local ptext = label(plate, 17, "CENTER", plate, "CENTER", 10, 0, GOLD, nil, 180)
    ptext:SetJustifyH("CENTER"); ptext:SetText("RING THE BELL")
    ui.tent, ui.plate, ui.plateBell = tent, plate, pbell
end

local function buildTower(pb)
    local tower = CreateFrame("Frame", nil, pb)
    tower:SetSize(60, POLE_H + 36)
    tower:SetPoint("TOPLEFT", pb, "TOPLEFT", 6, 0)
    local bell = tower:CreateTexture(nil, "OVERLAY")
    bell:SetSize(30, 30); bell:SetPoint("TOP", tower, "TOP", -6, 0); bell:SetTexture(Board.bellIcon())
    local pole = CreateFrame("Frame", nil, tower)
    pole:SetSize(14, POLE_H); pole:SetPoint("TOP", tower, "TOP", -6, -34)
    local pt = rect(pole, "BACKGROUND", { 0.69, 0.48, 0.23 }); pt:SetAllPoints(pole)
    gradient(pt, "HORIZONTAL", { 0.35, 0.23, 0.1 }, { 0.69, 0.48, 0.23 })
    local pt2 = rect(pole, "BACKGROUND", { 0.35, 0.23, 0.1 }, 7, POLE_H)
    pt2:SetPoint("TOPRIGHT", pole, "TOPRIGHT", 0, 0)
    gradient(pt2, "HORIZONTAL", { 0.69, 0.48, 0.23 }, { 0.35, 0.23, 0.1 })
    local fill = CreateFrame("Frame", nil, pole)
    fill:SetSize(14, 1); fill:SetPoint("BOTTOM", pole, "BOTTOM", 0, 0)
    local ft = rect(fill, "ARTWORK", { 0.9, 0.4, 0 }); ft:SetAllPoints(fill); ui.fillTex = ft
    gradient(ft, "VERTICAL", { 0.2, 0.7, 0.1 }, { 0.9, 0.4, 0 })
    local marker = CreateFrame("Frame", nil, pole)
    marker:SetSize(30, 3); marker:SetPoint("BOTTOM", pole, "BOTTOM", 0, 0)
    local mt = rect(marker, "OVERLAY", { 1, 1, 1 }); mt:SetAllPoints(marker)
    local mglow = marker:CreateTexture(nil, "ARTWORK")
    mglow:SetTexture(WHITE); mglow:SetVertexColor(1, 1, 1, 0.3); mglow:SetSize(36, 9); mglow:SetPoint("CENTER", marker, "CENTER", 0, 0)
    pcall(mglow.SetBlendMode, mglow, "ADD")
    ui.scaleTop = label(tower, 11, "LEFT", pole, "TOPRIGHT", 6, 0, GREY, nil, 40)
    ui.scaleMid = label(tower, 11, "LEFT", pole, "RIGHT", 6, 0, GREY, nil, 40)
    ui.tower, ui.bell, ui.pole, ui.fill, ui.marker = tower, bell, pole, fill, marker
end

local function build()
    local f = CreateFrame("Frame", "RingTheBellBoard", UIParent)
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local bg = rect(f, "BACKGROUND", INK); bg:SetAllPoints(f)
    border(f, GOLD2, 3)
    buildTent(f)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "RingTheBellBoard") end

    -- ticket tabs along the bottom
    ui.tabs = {}
    local x = 84
    for _, t in ipairs({ { "board", "Board" }, { "history", "History" }, { "options", "Options" } }) do
        local b = button(f, t[2], 80, "BOTTOMLEFT", f, "BOTTOMLEFT", x, 10)
        local key = t[1]
        b:SetScript("OnClick", function() showTab(key); Board.refresh() end)
        ui.tabs[key] = b
        x = x + 88
    end

    local function page(key, left)
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", f, "TOPLEFT", left, -(TENT_H + 12))
        p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 44)
        pages[key] = p
        return p
    end

    -- Board page: tower on the left, champion card and the newest records on the right
    local pb = page("board", 18)
    buildTower(pb)
    local card = CreateFrame("Frame", nil, pb)
    card:SetPoint("TOPLEFT", pb, "TOPLEFT", 66, 0)
    card:SetPoint("TOPRIGHT", pb, "TOPRIGHT", 0, 0)
    card:SetSize(FRAME_W - 18 - 16 - 66, 104)
    local cbg = rect(card, "BACKGROUND", { 1, 1, 1 }); cbg:SetAllPoints(card); cbg:SetVertexColor(1, 1, 1, 0.05)
    border(card, { 0.78, 0.59, 0.16, 0.4 }, 1)
    ui.glow = card:CreateTexture(nil, "BACKGROUND")
    ui.glow:SetTexture(GLOW); ui.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.8)
    ui.glow:SetSize(104, 104); ui.glow:SetPoint("CENTER", card, "LEFT", 40, 0)
    pcall(ui.glow.SetBlendMode, ui.glow, "ADD")
    ui.champFrame = rect(card, "BORDER", GOLD2, 60, 60); ui.champFrame:SetPoint("LEFT", card, "LEFT", 10, 0)
    ui.champIcon = card:CreateTexture(nil, "ARTWORK")
    ui.champIcon:SetSize(56, 56); ui.champIcon:SetPoint("CENTER", ui.champFrame, "CENTER", 0, 0)
    pcall(ui.champIcon.SetTexCoord, ui.champIcon, 0.08, 0.92, 0.08, 0.92)
    ui.cardLabel = label(card, 11, "TOPLEFT", card, "TOPLEFT", 82, -8, GREY, nil, 120); ui.cardLabel:SetText("CHAMPION")
    ui.name = label(card, 20, "TOPLEFT", card, "TOPLEFT", 82, -21, GOLD, "OUTLINE", 330)
    ui.amount = label(card, 34, "TOPLEFT", card, "TOPLEFT", 82, -44, GOLD, "OUTLINE", 330)
    pcall(ui.amount.SetShadowColor, ui.amount, 1, 0.7, 0, 0.5); pcall(ui.amount.SetShadowOffset, ui.amount, 2, -2)
    ui.card = card
    ui.meta = label(card, 12, "BOTTOMLEFT", card, "BOTTOMLEFT", 82, 6, GREY, nil, 330)
    ui.hint = label(card, 16, "TOPLEFT", card, "TOPLEFT", 20, -30, CREAM, nil, 380)
    ui.hint2 = label(card, 13, "TOPLEFT", ui.hint, "BOTTOMLEFT", 0, -8, GOLD, nil, 380)
    ui.recentLabel = label(pb, 11, "TOPLEFT", pb, "TOPLEFT", 68, -112, GOLD2, nil, 200); ui.recentLabel:SetText("LEADERBOARD")
    ui.boardRows = {}
    local rowsHolder = CreateFrame("Frame", nil, pb)
    rowsHolder:SetPoint("TOPLEFT", pb, "TOPLEFT", 66, -128)
    rowsHolder:SetSize(FRAME_W - 18 - 16 - 66, BOARD_ROWS * ROW_H)
    for i = 1, BOARD_ROWS do ui.boardRows[i] = makeRow(rowsHolder, -(i - 1) * ROW_H, FRAME_W - 18 - 16 - 66) end

    -- History page: same rows, scrolling
    local ph = page("history", 16)
    local scroll = CreateFrame("ScrollFrame", "RingTheBellHistoryScroll", ph, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", ph, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", ph, "BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(FRAME_W - 16 - 16 - 30, HIST_MAX * ROW_H)
    scroll:SetScrollChild(child)
    ui.scroll, ui.histChild = scroll, child
    ui.histRows = {}
    for i = 1, HIST_MAX do ui.histRows[i] = makeRow(child, -(i - 1) * ROW_H, FRAME_W - 16 - 16 - 30) end
    ui.histEmpty = label(ph, 14, "TOPLEFT", ph, "TOPLEFT", 10, -10, CREAM, nil, 300)
    ui.histEmpty:SetText("No records yet.")

    -- Options page
    local po = page("options", 16)
    local fl = label(po, 13, "TOPLEFT", po, "TOPLEFT", 10, -4, GOLD, nil, 440); fl:SetText("Who is on the board")
    ui.whoHint = label(po, 12, "TOPLEFT", po, "TOPLEFT", 10, -24, GREY, nil, 440)
    ui.whoHint:SetText("Everyone in your guild who runs Ring the Bell.")
    ui.sound = checkbox(po, "Bell sound", -52, "sound")
    ui.popup = checkbox(po, "Record popup", -76, "popup")
    ui.pip = checkbox(po, "Minimap bell", -100, "pip")
    ui.resetPopup = button(po, "Reset popup position", 150, "TOPLEFT", po, "TOPLEFT", 10, -134)
    ui.resetPopup:SetScript("OnClick", resetPopup)
    ui.clear = button(po, "Clear my local copy", 150, "LEFT", ui.resetPopup, "RIGHT", 8, 0)
    ui.clear:SetScript("OnClick", clearLocal)
    ui.push = button(po, "Push update", 150, "LEFT", ui.clear, "RIGHT", 8, 0)
    ui.push:SetScript("OnClick", function() if RB.pushUpdate then RB.pushUpdate() end end)
    Board.pushButton = ui.push
    Board.setPushEnabled(pushEnabled)

    f:Hide()
    frame = f
    Board.ui = ui
    showTab("board")
    return f
end

-- public -------------------------------------------------------------------------------------------------------------
function Board.toggle()
    local f = frame or build()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        Board.refresh()
    end
end

function Board.isShown() return frame ~= nil and frame:IsShown() end

-- the record hook: Banner (loaded earlier) is the original; the board redraws after it
local orig = RB.onRecord
RB.onRecord = function(...)
    if orig then orig(...) end
    Board.refresh()
end

-- NectarKit switches. Banner reads NectarKit_IsModuleOn live, so toggling needs no action beyond a redraw.
local function registerModules()
    local function on() Board.refresh() end
    NectarKit_RegisterModule("RingTheBell", "popup", "Record popup", true, on)
    NectarKit_RegisterModule("RingTheBell", "sound", "Bell sound", true, on)
end
if not NectarKit_RegisterModule then
    NectarKit_Queue = NectarKit_Queue or {}
    for _, m in ipairs({ { "popup", "Record popup" }, { "sound", "Bell sound" } }) do
        table.insert(NectarKit_Queue, { addon = "RingTheBell", key = m[1], label = m[2], default = true, onToggle = function() Board.refresh() end })
    end
end
local loginFrame = CreateFrame("Frame")
pcall(loginFrame.RegisterEvent, loginFrame, "PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    if NectarKit_RegisterModule then pcall(registerModules) end
end)
