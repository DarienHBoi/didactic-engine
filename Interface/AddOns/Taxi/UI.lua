-- Taxi UI: tabs Going | Stay | LFG, class + place search, tick list, message, Send.
local ADDON, ns = ...

local W, H = 400, 560
local ROW_H = 20
local f = CreateFrame("Frame", "TaxiFrame", UIParent, "BasicFrameTemplateWithInset")
f:SetSize(W, H)
f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetClampedToScreen(true)
f:Hide()
tinsert(UISpecialFrames, "TaxiFrame")

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", f, "TOP", 0, -6)
title:SetText("TAXI")

local results = {}      -- current list for the active tab: { {name, level, area, class}, ... }
local note = ""         -- truncation note or error shown under the list
local rows = {}

local function db() return ns.GetDB() end
local function tab() return db().tab end

local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
status:SetWidth(W - 28)
status:SetJustifyH("LEFT")
local function say(text) status:SetText(text or "") end

-- ---- tabs ----
local tabButtons = {}
local refresh -- forward
for i, name in ipairs(ns.TABS) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(80, 24)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + (i - 1) * 84, -30)
    b:SetText(name)
    b:SetScript("OnClick", function()
        db().tab = name
        say("")
        refresh()
    end)
    tabButtons[name] = b
end

-- ---- search controls ----
local classBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
classBtn:SetSize(100, 24)
classBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -62)
classBtn:SetScript("OnClick", function()
    local cur = db().class[tab()]
    local idx = 1
    for i, c in ipairs(ns.CLASSES) do if c == cur then idx = i end end
    db().class[tab()] = ns.CLASSES[idx % #ns.CLASSES + 1]
    refresh()
end)

local placeBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
placeBox:SetSize(170, 22)
placeBox:SetPoint("LEFT", classBtn, "RIGHT", 14, 0)
placeBox:SetAutoFocus(false)
placeBox:SetMaxLetters(60)
placeBox:SetScript("OnEscapePressed", placeBox.ClearFocus)
placeBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); f.DoSearch() end)
placeBox:SetScript("OnTextChanged", function(self, user) if user then db().place[tab()] = self:GetText() end end)

local placeHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
placeHint:SetPoint("BOTTOMLEFT", placeBox, "TOPLEFT", 2, 0)
placeHint:SetText("Where (zone name)")

local searchBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
searchBtn:SetSize(80, 24)
searchBtn:SetPoint("LEFT", placeBox, "RIGHT", 8, 0)
searchBtn:SetText("Search")

-- ---- table header ----
local lvlLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
lvlLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -96)
lvlLabel:SetText("Level")
local function levelBox(anchorTo, dx, key)
    local b = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    b:SetSize(34, 20)
    b:SetPoint("LEFT", anchorTo, "RIGHT", dx, 0)
    b:SetAutoFocus(false)
    b:SetMaxLetters(2)
    b:SetNumeric(true)
    b:SetScript("OnEscapePressed", b.ClearFocus)
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus(); f.DoSearch() end)
    b:SetScript("OnTextChanged", function(self, user) if user then db()[key][tab()] = self:GetText() end end)
    return b
end
local minBox = levelBox(lvlLabel, 14, "lmin")
local toLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
toLabel:SetPoint("LEFT", minBox, "RIGHT", 6, 0)
toLabel:SetText("to")
local maxBox = levelBox(toLabel, 10, "lmax")
local lvlHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lvlHint:SetPoint("LEFT", maxBox, "RIGHT", 10, 0)
lvlHint:SetText("(blank = any)")

-- dungeon picker (LFG tab only): popup list sorted by level
local dungeonBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
dungeonBtn:SetSize(150, 22)
dungeonBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 232, -94)
dungeonBtn:SetText("Pick dungeon...")

local popup = CreateFrame("Frame", nil, f)
popup:SetSize(250, #ns.DUNGEONS * 18 + 8)
popup:SetPoint("TOPRIGHT", dungeonBtn, "BOTTOMRIGHT", 0, -2)
popup:SetFrameStrata("DIALOG")
local pbg = popup:CreateTexture(nil, "BACKGROUND")
pbg:SetAllPoints()
pbg:SetColorTexture(0.06, 0.05, 0.04, 0.97)
popup:Hide()
for i, d in ipairs(ns.DUNGEONS) do
    local b = CreateFrame("Button", nil, popup)
    b:SetSize(242, 18)
    b:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -4 - (i - 1) * 18)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", b, "LEFT", 4, 0)
    b:SetFontString(fs)
    b:SetText(("%s  |cffaaaaaa%d-%d|r"):format(d[1], d[2], d[3]))
    b:SetScript("OnClick", function()
        ns.ApplyDungeon(tab(), d)
        popup:Hide()
        refresh()
    end)
end
dungeonBtn:SetScript("OnClick", function() if popup:IsShown() then popup:Hide() else popup:Show() end end)

local hdrY = -122
local function hdr(text, x)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, hdrY)
    fs:SetText(text)
end
hdr("Name", 40); hdr("lvl", 190); hdr("Where", 225)

-- ---- list ----
local scroll = CreateFrame("ScrollFrame", "TaxiScroll", f, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, hdrY - 16)
scroll:SetSize(W - 44, 224)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(W - 50, 10)
scroll:SetScrollChild(content)

local function getRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, content)
    r:SetSize(W - 50, ROW_H)
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(22, 22)
    r.check:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.check:SetScript("OnClick", function(self)
        ns.ticked[tab()][r.name] = self:GetChecked() and true or nil
    end)
    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.nameText:SetPoint("LEFT", r, "LEFT", 28, 0)
    r.nameText:SetWidth(145)
    r.nameText:SetJustifyH("LEFT")
    r.lvl = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.lvl:SetPoint("LEFT", r, "LEFT", 178, 0)
    r.where = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.where:SetPoint("LEFT", r, "LEFT", 212, 0)
    r.where:SetWidth(110)
    r.where:SetJustifyH("LEFT")
    rows[i] = r
    return r
end

local function drawList()
    local t = tab()
    for i, p in ipairs(results) do
        local r = getRow(i)
        r.name = p.name
        local sent = ns.IsSent(t, p.name)
        local off = ns.IsOffline(t, p.name)
        r.nameText:SetText(sent and (p.name .. " |cff888888(sent)|r") or off and (p.name .. " |cffff6666(offline)|r") or p.name)
        r.lvl:SetText(p.level or "")
        r.where:SetText(p.area or "")
        r.check:SetChecked(ns.ticked[t][p.name] and true or false)
        r:Show()
    end
    for i = #results + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(10, #results * ROW_H))
end

ns.onOffline = function(name) drawList() end

-- ---- message + send ----
local msgBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
msgBox:SetSize(W - 40, 22)
msgBox:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 8, -26)
msgBox:SetAutoFocus(false)
msgBox:SetMaxLetters(255)
msgBox:SetScript("OnEscapePressed", msgBox.ClearFocus)
msgBox:SetScript("OnEnterPressed", msgBox.ClearFocus)
msgBox:SetScript("OnTextChanged", function(self, user) if user then db().msg[tab()] = self:GetText() end end)
local msgHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
msgHint:SetPoint("BOTTOMLEFT", msgBox, "TOPLEFT", -2, 0)
msgHint:SetText("Message (paste here, sent to every ticked player)")

local sendBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
sendBtn:SetSize(110, 26)
sendBtn:SetPoint("TOPLEFT", msgBox, "BOTTOMLEFT", -6, -10)
sendBtn:SetText("Send to ticked")

local stopBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
stopBtn:SetSize(60, 26)
stopBtn:SetPoint("LEFT", sendBtn, "RIGHT", 6, 0)
stopBtn:SetText("Stop")

local allBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
allBtn:SetSize(90, 22)
allBtn:SetPoint("TOPLEFT", sendBtn, "BOTTOMLEFT", 0, -6)
allBtn:SetText("Tick all")

local noneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
noneBtn:SetSize(90, 22)
noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)
noneBtn:SetText("Tick none")

local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
clearBtn:SetSize(110, 22)
clearBtn:SetPoint("LEFT", noneBtn, "RIGHT", 6, 0)
clearBtn:SetText("Clear 'sent'")

-- ---- actions ----
function f.DoSearch()
    local t = tab()
    say("Searching...")
    ns.Search(db().class[t], db().place[t], db().lmin[t], db().lmax[t], function(list, info)
        if not list then say("|cffff6666" .. info .. "|r"); return end
        results = list
        db().results[t] = list
        note = info or ""
        say(#list .. " players" .. (note ~= "" and ("  -  " .. note) or ""))
        drawList()
    end)
end
searchBtn:SetScript("OnClick", function() placeBox:ClearFocus(); f.DoSearch() end)

local function tickedNames()
    local t, names = tab(), {}
    for _, p in ipairs(results) do
        if ns.ticked[t][p.name] then names[#names + 1] = p.name end
    end
    return names
end

sendBtn:SetScript("OnClick", function()
    msgBox:ClearFocus()
    local t = tab()
    local n, why = ns.StartSend(t, tickedNames(), msgBox:GetText(),
        function(i, total, name, ok) say(("Sending %d/%d: %s%s"):format(i, total, name, ok and "" or " (failed)")); drawList() end,
        function(sent, failed, stopped)
            say(("%s: %d sent, %d failed."):format(stopped and "Stopped" or "Done", sent, failed))
            drawList()
        end)
    if not n then say("|cffff6666" .. why .. "|r") end
end)
stopBtn:SetScript("OnClick", function() ns.StopSend() end)
allBtn:SetScript("OnClick", function()
    local t = tab()
    for _, p in ipairs(results) do if not ns.IsSent(t, p.name) then ns.ticked[t][p.name] = true end end
    drawList()
end)
noneBtn:SetScript("OnClick", function() ns.ticked[tab()] = {}; drawList() end)
clearBtn:SetScript("OnClick", function() ns.ClearMarks(tab()); drawList(); say("Sent marks cleared for " .. tab() .. ".") end)

function refresh()
    local t = tab()
    popup:Hide()
    if t == "LFG" then dungeonBtn:Show(); lvlHint:Hide() else dungeonBtn:Hide(); lvlHint:Show() end
    results = db().results[t]
    for name, b in pairs(tabButtons) do
        if name == t then b:Disable() else b:Enable() end
    end
    classBtn:SetText(db().class[t])
    placeBox:SetText(db().place[t])
    minBox:SetText(db().lmin[t])
    maxBox:SetText(db().lmax[t])
    msgBox:SetText(db().msg[t])
    msgBox:SetCursorPosition(0)
    drawList()
end

f:SetScript("OnShow", refresh)

SLASH_TAXI1 = "/taxi"
SlashCmdList["TAXI"] = function()
    if f:IsShown() then f:Hide() else f:Show() end
end
