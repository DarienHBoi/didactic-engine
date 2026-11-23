-- !ErrorLog: keeps Lua errors in ErrorLogDB (written to disk on /reload or logout). Same message = one entry with a count.
-- Errors also go to a small movable box instead of Blizzard's big "Lua Error" window (/errlog blizz brings the window back).
local MAX = 300
local FADE_AFTER, FADE_ALPHA = 8, 0.35
local DEFAULT_POS = { "LEFT", "LEFT", 20, 100 }
local pending = {}   -- errors before ADDON_LOADED (our saved table is not loaded yet)
local DB

local M = { moduleOn = true, list = {}, total = 0, idx = 0 }  -- M.list: distinct errors seen this session, oldest first
ErrorLog = M

local function now() return date and date("%Y-%m-%d %H:%M:%S") or "?" end

-- ---------------------------------------------------------------- compact mode and the Blizzard window

-- True when errors go to the box and Blizzard's window is held back.
local function compact() return DB ~= nil and M.moduleOn and not DB.blizz end

local function popupAllowed()
    local ok, v = pcall(GetCVar, "scriptErrors")   -- /console scriptErrors 0 means "show nothing"
    return not ok or v == nil or tostring(v) ~= "0"
end

local function hideBlizz()
    if not compact() then return end
    local f = _G.ScriptErrorsFrame
    if f and f.Hide then pcall(f.Hide, f) end
end

local hooked
local function hookBlizz()
    local f = _G.ScriptErrorsFrame
    if hooked or not f then return end
    hooked = true
    pcall(hooksecurefunc, f, "Show", hideBlizz)
    if f.HookScript then pcall(f.HookScript, f, "OnShow", hideBlizz) end
end

-- ---------------------------------------------------------------- the box

local GOLD, BG, BORDER = { 1, 0.82, 0.27 }, { 0.08, 0.08, 0.075, 0.95 }, { 0.48, 0.40, 0.27, 1 }
local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local function style(f)
    pcall(function()
        if not f.SetBackdrop then return end
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(BG[1], BG[2], BG[3], BG[4])
        f:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
    end)
end

local function addonOf(e)
    return e.msg:match("AddOns[\\/]([^\\/]+)[\\/]") or "?"
end

-- First line only, without the Interface\AddOns\<name>\ prefix.
local function oneLine(e)
    local line = e.msg:match("^[^\r\n]*") or ""
    return (line:gsub("^.-AddOns[\\/][^\\/]+[\\/]", "", 1))
end

local function fullText(e)
    local t = e.msg
    if e.stack and e.stack ~= "" then t = t .. "\n\n" .. e.stack end
    return t
end

local function current() return M.list[M.idx] end

local function applyPos(b)
    local p = DB and DB.box and DB.box.pos or DEFAULT_POS
    b:ClearAllPoints()
    b:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function render()
    local b = M.box
    if not b then return end
    local n = #M.list
    if n == 0 then
        b.count:SetText("0 errors"); b.line:SetText(""); b.idx:SetText("")
        return
    end
    if M.idx > n then M.idx = n end
    if M.idx < 1 then M.idx = 1 end
    local e = M.list[M.idx]
    b.count:SetText(M.total == 1 and "1 error" or (M.total .. " errors"))
    b.idx:SetText(n > 1 and (M.idx .. "/" .. n) or "")
    b.line:SetText(addonOf(e) .. ": " .. oneLine(e))
end

local function showTip()
    local b, e = M.box, current()
    if not b or not e then return end
    if not M.tip then
        local t = CreateFrame("Frame", "ErrorLogTip", UIParent, TEMPLATE)
        t:SetFrameStrata("TOOLTIP")
        style(t)
        t:SetWidth(520)
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t.text:SetPoint("TOPLEFT", 8, -8)
        t.text:SetWidth(504)
        t.text:SetJustifyH("LEFT")
        t.text:SetJustifyV("TOP")
        M.tip = t
    end
    local t = M.tip
    local txt = fullText(e)
    if #txt > 2000 then txt = txt:sub(1, 2000) .. "\n..." end
    t.text:SetText(txt)
    t:SetHeight(math.min(600, (t.text:GetStringHeight() or 40) + 16))
    t:ClearAllPoints()
    local left = true
    pcall(function() left = (b:GetCenter() or 0) < (UIParent:GetWidth() or 0) / 2 end)
    if left then t:SetPoint("TOPLEFT", b, "TOPRIGHT", 6, 0) else t:SetPoint("TOPRIGHT", b, "TOPLEFT", -6, 0) end
    t:Show()
end

local function hideTip() if M.tip then M.tip:Hide() end end

local function closeMenu() if M.menu then M.menu:Hide() end end

local function showCopy()
    local e = current()
    if not e then return end
    if not M.copy then
        local c = CreateFrame("Frame", "ErrorLogCopy", UIParent, TEMPLATE)
        c:SetSize(560, 220)
        c:SetPoint("CENTER")
        c:SetFrameStrata("DIALOG")
        style(c)
        local sf = CreateFrame("ScrollFrame", "ErrorLogCopyScroll", c, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 10, -10)
        sf:SetPoint("BOTTOMRIGHT", -30, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject("ChatFontNormal")
        eb:SetWidth(510)
        eb:SetScript("OnEscapePressed", function() c:Hide() end)
        sf:SetScrollChild(eb)
        c.edit = eb
        M.copy = c
    end
    M.copy.edit:SetText(fullText(e))
    M.copy:Show()
    M.copy.edit:SetFocus()
    M.copy.edit:HighlightText()
end

local function clearBox()
    M.list, M.total, M.idx = {}, 0, 0
    render()
    hideTip()
    if M.box then M.box:Hide() end
end

local function hideBox()
    if M.box then M.box:Hide() end
    hideTip(); closeMenu()
end

local function ensureMenu()
    if M.menu then return M.menu end
    local m = CreateFrame("Frame", "ErrorLogMenu", UIParent, TEMPLATE)
    m:SetSize(150, 3 * 20 + 8)
    m:SetFrameStrata("DIALOG")
    style(m)
    m.buttons = {}
    local actions = {
        { "copy", "Copy", function() closeMenu(); showCopy() end },
        { "clear", "Clear", function() closeMenu(); clearBox() end },
        { "hide", "Hide until next error", function() closeMenu(); hideBox() end },
    }
    for i, a in ipairs(actions) do
        local bt = CreateFrame("Button", nil, m)
        bt:SetSize(142, 20)
        bt:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
        bt:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        bt.label = bt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bt.label:SetPoint("LEFT", 6, 0)
        bt.label:SetText(a[2])
        bt.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        bt.action = a[1]
        bt:SetScript("OnClick", a[3])
        m.buttons[i] = bt
    end
    m:Hide()
    M.menu = m
    return m
end

local function ensureBox()
    if M.box then return M.box end
    local b = CreateFrame("Button", "ErrorLogBox", UIParent, TEMPLATE)
    b:SetSize(300, 60)
    b:SetFrameStrata("HIGH")
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    style(b)
    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.count:SetPoint("TOPLEFT", 10, -9)
    b.count:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    b.idx = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.idx:SetPoint("TOPRIGHT", -10, -10)
    b.line = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.line:SetPoint("TOPLEFT", b.count, "BOTTOMLEFT", 0, -6)
    b.line:SetWidth(280)
    b.line:SetJustifyH("LEFT")
    b.line:SetWordWrap(false)
    if b.line.SetMaxLines then b.line:SetMaxLines(1) end
    b.idle, b.hover, b.dragStopped = 0, false, -1
    applyPos(b)

    b:SetScript("OnDragStart", function(self)
        if DB and DB.box and DB.box.locked then return end
        self:StartMoving()
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.dragStopped = GetTime()
        local p, _, rp, x, y = self:GetPoint()
        if p and DB then
            DB.box = DB.box or {}
            DB.box.pos = { p, rp, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
        end
    end)
    b:SetScript("OnClick", function(self, button)
        if GetTime() - self.dragStopped < 0.15 then return end   -- the mouse-up that ends a drag is not a click
        self.idle = 0
        if button == "RightButton" then
            local m = ensureMenu()
            if m:IsShown() then m:Hide() else
                m:ClearAllPoints()
                m:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
                m:Show()
            end
        else
            local n = #M.list
            if n > 0 then
                M.idx = M.idx % n + 1
                render()
                if M.tip and M.tip:IsShown() then showTip() end
            end
        end
    end)
    b:SetScript("OnEnter", function(self) self.hover = true; self:SetAlpha(1); showTip() end)
    b:SetScript("OnLeave", function(self) self.hover = false; self.idle = 0; hideTip() end)
    b:SetScript("OnUpdate", function(self, dt)
        self.idle = self.idle + (dt or 0)
        if self.idle > FADE_AFTER and not self.hover and self:GetAlpha() > FADE_ALPHA then self:SetAlpha(FADE_ALPHA) end
    end)
    M.box = b
    return b
end

-- Show the box with the current list (used by new errors and by /errlog box).
local function showBox()
    local b = ensureBox()
    render()
    b.idle = 0
    b:SetAlpha(1)
    b:Show()
end

local function wantBox() return compact() and not (DB.box and DB.box.off) end

local function notify(kind, e)
    if kind ~= "error" then return end
    M.total = M.total + 1
    for i, x in ipairs(M.list) do
        if x == e then table.remove(M.list, i) break end
    end
    M.list[#M.list + 1] = e
    M.idx = #M.list
    if M.box then render() end
    if wantBox() and popupAllowed() then pcall(showBox) end
end

-- ---------------------------------------------------------------- recording (unchanged behaviour)

local function store(kind, msg, stack)
    msg = tostring(msg)
    if not DB then pending[#pending + 1] = { kind, msg, stack, now() } return end
    local key = kind .. "|" .. msg
    local e = DB.index[key]
    if e then
        e.count, e.last = e.count + 1, now()
        pcall(notify, kind, e)
        return
    end
    e = { kind = kind, msg = msg, stack = stack, first = now(), last = now(), count = 1, session = DB.session }
    DB.list[#DB.list + 1] = e
    DB.index[key] = e
    while #DB.list > MAX do
        local old = table.remove(DB.list, 1)
        DB.index[old.kind .. "|" .. old.msg] = nil
    end
    pcall(notify, kind, e)
end

local previous = geterrorhandler()
seterrorhandler(function(msg, ...)
    pcall(store, "error", msg, debugstack and debugstack(3, 20, 0) or "")
    if compact() then
        pcall(hideBlizz)   -- never show Blizzard's window; the box has it
        return
    end
    if previous then return previous(msg, ...) end
end)
pcall(hookBlizz)

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_ACTION_BLOCKED")
f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
pcall(f.RegisterEvent, f, "LUA_WARNING")
f:SetScript("OnEvent", function(_, event, a, b)
    if event == "ADDON_LOADED" then
        if a ~= "!ErrorLog" then return end
        ErrorLogDB = ErrorLogDB or {}
        DB = ErrorLogDB
        DB.list = DB.list or {}
        DB.index = {}
        DB.box = DB.box or {}
        for _, e in ipairs(DB.list) do DB.index[e.kind .. "|" .. e.msg] = e end
        DB.session = (DB.session or 0) + 1
        DB.sessionStart = DB.sessionStart or {}
        DB.sessionStart[DB.session] = now()
        for _, p in ipairs(pending) do store(p[1], p[2], p[3]) end
        pending = {}
        pcall(hookBlizz)
    elseif event == "PLAYER_LOGIN" then
        pcall(hookBlizz)   -- ScriptErrorsFrame may not have existed at file load
        pcall(hideBlizz)
    elseif event == "LUA_WARNING" then
        store("warning", tostring(b or a), "")
    else
        store("blocked", tostring(a) .. " tried " .. tostring(b), debugstack and debugstack(2, 12, 0) or "")
    end
end)

-- ---------------------------------------------------------------- NectarKit module switch

local function onToggle(on)
    M.moduleOn = on and true or false
    if M.moduleOn then pcall(hideBlizz) else pcall(hideBox) end
end

if NectarKit_RegisterModule then
    pcall(NectarKit_RegisterModule, "!ErrorLog", "compact", "Compact error box", true, onToggle)
else   -- !ErrorLog loads before NectarKit: leave a record, NectarKit drains it
    NectarKit_Queue = NectarKit_Queue or {}
    table.insert(NectarKit_Queue, { addon = "!ErrorLog", key = "compact", label = "Compact error box", default = true,
        onToggle = onToggle })
end

-- ---------------------------------------------------------------- slash command

local function say(t) print("!ErrorLog: " .. t) end

SLASH_ERRORLOG1 = "/errlog"
SlashCmdList.ERRORLOG = function(arg)
    arg = tostring(arg or ""):lower():match("^%s*(.-)%s*$")
    if arg == "clear" and DB then
        DB.list, DB.index = {}, {}
        say("cleared.")
    elseif (arg == "box" or arg == "reset" or arg == "lock" or arg == "blizz") then
        if not DB then say("not loaded yet.") return end
        DB.box = DB.box or {}
        if arg == "box" then
            -- toggles by what you see: visible -> off, otherwise on (an empty box is shown so it can be placed)
            if M.box and M.box:IsShown() then DB.box.off = true else DB.box.off = nil end
            if DB.box.off then
                hideBox()
                say("box off (errors are still counted; /errlog box to show it).")
            elseif compact() then
                pcall(showBox)
                say("box on.")
            else
                say("box on, but the Blizzard window is in use (/errlog blizz or the NectarKit switch).")
            end
        elseif arg == "reset" then
            DB.box.pos = nil
            if M.box then applyPos(M.box) end
            say("box position reset.")
        elseif arg == "lock" then
            DB.box.locked = not DB.box.locked
            say(DB.box.locked and "box locked." or "box unlocked, drag it with the left mouse button.")
        else
            DB.blizz = not DB.blizz
            if DB.blizz then
                hideBox()
                say("Blizzard's error window is back. /errlog blizz returns to the small box.")
            else
                pcall(hideBlizz)
                say("small error box is back.")
            end
        end
    else
        print(("!ErrorLog: %d different errors saved. /reload to write them to disk; /errlog clear to empty."):format(DB and #DB.list or 0))
        print("!ErrorLog: /errlog box | reset | lock | blizz")
    end
end
