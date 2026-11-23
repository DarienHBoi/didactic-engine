-- /reaper options window, dark and gold like Pricewatch's theme. Built on first use.
local _, R = ...
local L, M = R.Logic, R.Main
local O = { controls = {} }
R.Options = O

local WHITE = "Interface\\Buttons\\WHITE8X8"
local WIDTH, HEIGHT = 330, 300
local STEP = 0.1

local win
local c = O.controls

local BTN = { bg = { 0.12, 0.115, 0.105, 0.98 }, border = { 0.48, 0.40, 0.27, 1 }, text = { 1, 0.82, 0.27 },
    pbg = { 0.22, 0.165, 0.05, 0.98 }, pborder = { 0.9, 0.72, 0.22, 1 }, ptext = { 1, 0.9, 0.4 } }

local function backdrop(f, edge, inset)
    if not f.SetBackdrop then return false end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
        edgeSize = edge, insets = { left = inset, right = inset, top = inset, bottom = inset } })
    return true
end

local function template() return BackdropTemplateMixin and "BackdropTemplate" or nil end

local function button(parent, text, w, h, primary)
    local b = CreateFrame("Button", nil, parent, template())
    b:SetSize(w, h)
    local bg, border, tc = BTN.bg, BTN.border, BTN.text
    if primary then bg, border, tc = BTN.pbg, BTN.pborder, BTN.ptext end
    if backdrop(b, 12, 4) then
        b:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        b:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("CENTER")
    b.label:SetTextColor(tc[1], tc[2], tc[3])
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.SetText = function(self, t) self.label:SetText(t or "") end
    b.GetText = function(self) return self.label:GetText() end
    b:SetText(text)
    return b
end

local function check(parent, text, onClick)
    local ok, cb = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
    if not ok or not cb then cb = CreateFrame("CheckButton", nil, parent) end
    cb:SetSize(24, 24)
    cb.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.label:SetText(text)
    cb:SetScript("OnClick", onClick)
    return cb
end

local function setLead(v)
    v = math.floor(v * 10 + 0.5) / 10
    M.db.leadTime = math.max(0, math.min(L.MAX_LEAD, v))
    O.refresh()
end

local function setIcon(v)
    M.setOption("iconSize", v)
    O.refresh()
end

function O.refresh()
    if not win then return end
    c.leadText:SetText(string.format("%.1f s", M.db.leadTime))
    c.sizeText:SetText(M.db.iconSize .. " px")
    c.iconCheck:SetChecked(M.db.plateIcon)
    c.flashCheck:SetChecked(M.db.buttonFlash)
    c.tickCheck:SetChecked(M.db.tick)
    c.testButton:SetText(M.testOn() and "Stop test" or "Test on target")
    c.status:SetText(M.status())
end

local function build()
    win = CreateFrame("Frame", "ReaperOptions", UIParent, template())
    win:SetSize(WIDTH, HEIGHT)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if backdrop(win, 12, 3) then
        win:SetBackdropColor(0.06, 0.055, 0.05, 0.97)
        win:SetBackdropBorderColor(0.48, 0.40, 0.27, 1)
    end
    table.insert(UISpecialFrames, "ReaperOptions")

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Reaper")
    title:SetTextColor(1, 0.82, 0)
    local close = button(win, "x", 22, 22)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() win:Hide() end)

    c.status = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    c.status:SetPoint("TOPLEFT", 16, -40)
    c.status:SetWidth(WIDTH - 32)
    c.status:SetJustifyH("LEFT")

    -- lead time
    local lead = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lead:SetPoint("TOPLEFT", 16, -82)
    lead:SetText("Reaction time: DoT damage landing this soon counts")
    c.leadMinus = button(win, "-", 26, 22)
    c.leadMinus:SetPoint("TOPLEFT", 16, -102)
    c.leadMinus:SetScript("OnClick", function() setLead(M.db.leadTime - STEP) end)
    c.leadText = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.leadText:SetPoint("LEFT", c.leadMinus, "RIGHT", 10, 0)
    c.leadText:SetWidth(50)
    c.leadPlus = button(win, "+", 26, 22)
    c.leadPlus:SetPoint("LEFT", c.leadMinus, "RIGHT", 70, 0)
    c.leadPlus:SetScript("OnClick", function() setLead(M.db.leadTime + STEP) end)

    local function toggle(key)
        return function(self)
            M.setOption(key, self:GetChecked() and true or false)
            O.refresh()
        end
    end
    c.iconCheck = check(win, "SW:D icon on the target's plate", toggle("plateIcon"))
    c.iconCheck:SetPoint("TOPLEFT", 12, -132)
    c.flashCheck = check(win, "Soft glow on the SW:D action button", toggle("buttonFlash"))
    c.flashCheck:SetPoint("TOPLEFT", 12, -158)
    c.tickCheck = check(win, "Thin kill tick on plates", toggle("tick"))
    c.tickCheck:SetPoint("TOPLEFT", 12, -184)

    local sizeLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeLabel:SetPoint("TOPLEFT", 16, -216)
    sizeLabel:SetText("Icon size")
    c.sizeMinus = button(win, "-", 26, 22)
    c.sizeMinus:SetPoint("TOPLEFT", 16, -236)
    c.sizeMinus:SetScript("OnClick", function() setIcon(M.db.iconSize - 1) end)
    c.sizeText = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.sizeText:SetPoint("LEFT", c.sizeMinus, "RIGHT", 10, 0)
    c.sizeText:SetWidth(50)
    c.sizePlus = button(win, "+", 26, 22)
    c.sizePlus:SetPoint("LEFT", c.sizeMinus, "RIGHT", 70, 0)
    c.sizePlus:SetScript("OnClick", function() setIcon(M.db.iconSize + 1) end)

    c.testButton = button(win, "Test on target", 150, 26, true)
    c.testButton:SetPoint("BOTTOMLEFT", 16, 14)
    c.testButton:SetScript("OnClick", function()
        M.setTest(not M.testOn())
        O.refresh()
    end)
    win:SetScript("OnShow", function() O.refresh() end)
    O.frame = win
    win:Hide() -- a new frame starts shown; toggle() shows it
end

function O.toggle()
    if not win then build() end
    if win:IsShown() then
        win:Hide()
    else
        win:Show()
        O.refresh()
    end
end
