local ADDON, ns = ...

local panel
ns.optControls = { group = {} }
local groupButton, buildDisplayOptions
local rows = {}   -- pooled row frames
local WIDTH = 340          -- left column (buff list)
local RIGHT_X = WIDTH + 4  -- right column (display settings)
local FULL_W = WIDTH + 300
local GROUP_ORDER = { SELF = "GROUP", GROUP = "OPTIONAL", OPTIONAL = "SELF" }

local function getRow(i)
    local r = rows[i]
    if r then return r end
    r = {}
    r.bg = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    r.bg:SetSize(WIDTH - 24, 26)
    r.bg:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    r.bg:EnableMouse(false)
    r.bg:SetFrameLevel(panel:GetFrameLevel() + 1)
    r.bg:SetBackdropColor(0.04, 0.03, 0.03, 0.85)
    r.bg:SetBackdropBorderColor(0.35, 0.3, 0.2, 0.9)
    r.check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    r.check:SetSize(24, 24)
    r.check:SetFrameLevel(panel:GetFrameLevel() + 5)
    r.label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.label:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.label:SetWidth(WIDTH - 170)
    r.label:SetJustifyH("LEFT")
    r.del = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    r.del:SetSize(22, 22)
    r.del:SetFrameLevel(panel:GetFrameLevel() + 5)
    -- Self / Group / Optional: which display group this buff goes in (click cycles)
    r.grp = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    r.grp:SetSize(70, 20)
    r.grp:SetFrameLevel(panel:GetFrameLevel() + 5)
    rows[i] = r
    return r
end

local function header(text, y)
    panel.headers = panel.headers or {}
    local h = panel.headers[text]
    if not h then
        h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h.line = panel:CreateTexture(nil, "ARTWORK")
        h.line:SetColorTexture(1, 0.82, 0, 0.35)
        h.line:SetHeight(1)
        panel.headers[text] = h
    end
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    h:SetText(text)
    h:Show()
    h.line:ClearAllPoints()
    h.line:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y - 16)
    h.line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, y - 16)
    h.line:Show()
    return h
end

-- cycle button on a buff row: Self -> Group -> Optional
groupButton = function(r, cfg, key, default, xOff)
    local function label() return ns.GROUP_NAMES[cfg.groups[key] or default] end
    r.grp:ClearAllPoints()
    r.grp:SetPoint("RIGHT", r.bg, "RIGHT", xOff, 0)
    r.grp:SetText(label())
    r.grp:SetScript("OnClick", function(self)
        cfg.groups[key] = GROUP_ORDER[cfg.groups[key] or default]
        self:SetText(label())
        ns.Refresh()
    end)
    r.grp:Show()
    ns.optControls.group[key] = r.grp
end

function ns.RefreshOptions()
    if not panel then return end
    local class = ns.PlayerClass()
    local cfg = ns.ClassConfig(class)
    for _, r in ipairs(rows) do r.bg:Hide(); r.check:Hide(); r.label:Hide(); r.del:Hide(); r.grp:Hide() end
    ns.optControls.group = {}
    if panel.headers then for _, h in pairs(panel.headers) do h:Hide(); h.line:Hide() end end

    local y, idx = -40, 0
    local builtin = ns.BUILTIN[class]
    header((class or "?") .. " buffs", y)
    y = y - 22
    if not builtin then
        panel.none:SetText("No built-in buffs for your class yet - add your own below.")
        panel.none:ClearAllPoints()
        panel.none:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
        panel.none:Show()
        y = y - 22
    else
        panel.none:Hide()
        for _, e in ipairs(builtin) do
            idx = idx + 1
            local r = getRow(idx)
            r.bg:ClearAllPoints(); r.bg:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y + 1); r.bg:Show()
            r.check:ClearAllPoints()
            r.check:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
            r.check:SetChecked(ns.IsBuiltinEnabled(class, e))
            r.check:SetScript("OnClick", function(self)
                cfg.enabled[e.key] = self:GetChecked() and true or false
                ns.Refresh()
            end)
            r.label:SetText(e.label)
            groupButton(r, cfg, e.key, e.group, -16)
            r.check:Show(); r.label:Show(); r.del:Hide()
            y = y - 24
        end
    end

    y = y - 8
    header("Your own buffs (spell name or ID)", y)
    y = y - 22
    for i, m in ipairs(cfg.manual) do
        idx = idx + 1
        local r = getRow(idx)
        r.bg:ClearAllPoints(); r.bg:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y + 1); r.bg:Show()
        r.check:ClearAllPoints()
        r.check:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
        r.check:SetChecked(m.enabled ~= false)
        r.check:SetScript("OnClick", function(self)
            m.enabled = self:GetChecked() and true or false
            ns.Refresh()
        end)
        r.label:SetText(m.input)
        local name = ns.ResolveSpell(tonumber(m.input) or m.input)
        groupButton(r, cfg, ns.ManualKey(name or m.input), "SELF", -40)
        r.del:ClearAllPoints()
        r.del:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, y + 1)
        r.del:SetScript("OnClick", function()
            table.remove(cfg.manual, i)
            ns.RefreshOptions()
            ns.Refresh()
        end)
        r.check:Show(); r.label:Show(); r.del:Show()
        y = y - 24
    end

    panel.edit:ClearAllPoints()
    panel.edit:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, y - 4)
    panel.add:ClearAllPoints()
    panel.add:SetPoint("LEFT", panel.edit, "RIGHT", 6, 0)
    panel.hint:ClearAllPoints()
    panel.hint:SetPoint("TOPLEFT", panel.edit, "BOTTOMLEFT", -6, -4)
    y = y - 52

    panel.unlock:ClearAllPoints()
    panel.unlock:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    panel.unlock:SetText(ns.db.locked and "Unlock (move/resize)" or "Lock")
    panel.reset:ClearAllPoints()
    panel.reset:SetPoint("LEFT", panel.unlock, "RIGHT", 8, 0)
    y = y - 34
    panel.scaleText:ClearAllPoints()
    panel.scaleText:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, y)
    panel.scaleText:SetText(("Scale: %.2f"):format(ns.db.scale))
    y = y - 22

    panel.footer:ClearAllPoints()
    panel.footer:SetPoint("TOP", panel, "TOPLEFT", WIDTH / 2, y)
    panel.footer:SetText(idx .. " buffs listed")
    ns.UpdateDisplayOptions()
    panel:SetHeight(math.max(-y + 28, panel.rightHeight or 0))
end

local function addManual()
    local text = strtrim(panel.edit:GetText() or "")
    if text == "" then return end
    local cfg = ns.ClassConfig(ns.PlayerClass())
    for _, m in ipairs(cfg.manual) do
        if string.lower(m.input) == string.lower(text) then
            print("|cffffd200MBW|r already tracking " .. text)
            return
        end
    end
    cfg.manual[#cfg.manual + 1] = { input = text, enabled = true }
    if not ns.ResolveSpell(tonumber(text) or text) then
        print("|cffffd200MBW|r '" .. text .. "' is not in your spellbook - matching a buff with exactly that name.")
    end
    panel.edit:SetText("")
    panel.edit:ClearFocus()
    ns.RefreshOptions()
    ns.Refresh()
end

----------------------------------------------------------------------
-- Right column: layout, size and spacing, look, grouping, when to show
----------------------------------------------------------------------
local LAYOUT_NAMES = { list = "Grouped list", strip = "Icon strip", panels = "Big panels" }
local LAYOUT_NEXT = { list = "strip", strip = "panels", panels = "list" }
local updaters = {}

local function rheader(text, y)
    local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", panel, "TOPLEFT", RIGHT_X + 4, y)
    h:SetText(text)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.35)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", RIGHT_X + 2, y - 16)
    line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, y - 16)
    return y - 22
end

local function button(y, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(220, 22)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", RIGHT_X + 6, y)
    b:SetScript("OnClick", function(self) onClick(self); ns.RefreshOptions() end)
    return b, y - 26
end

-- "-" / "+" buttons and the value; clamped and saved through ns.SetOption
local function stepper(key, label, step, lo, hi, fmt, y)
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("TOPLEFT", panel, "TOPLEFT", RIGHT_X + 62, y - 4)
    local function set(d)
        local v = ns.clamp(tonumber(string.format("%.2f", ns.db[key] + d)), lo, hi)
        ns.SetOption(key, v)
        ns.RefreshOptions()
    end
    local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    minus:SetSize(26, 20)
    minus:SetPoint("TOPLEFT", panel, "TOPLEFT", RIGHT_X + 6, y)
    minus:SetText("-")
    minus:SetScript("OnClick", function() set(-step) end)
    local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    plus:SetSize(26, 20)
    plus:SetPoint("TOPLEFT", panel, "TOPLEFT", RIGHT_X + 33, y)
    plus:SetText("+")
    plus:SetScript("OnClick", function() set(step) end)
    updaters[#updaters + 1] = function() t:SetText(label .. ": " .. string.format(fmt, ns.db[key])) end
    ns.optControls[key] = { minus = minus, plus = plus, text = t }
    return y - 24
end

local function checkbox(key, label, y)
    local c = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    c:SetPoint("TOPLEFT", panel, "TOPLEFT", RIGHT_X + 6, y + 2)
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", c, "RIGHT", 2, 0)
    t:SetText(label)
    -- flip the saved value (not GetChecked) so the box always matches what is saved
    c:SetScript("OnClick", function(self)
        ns.SetOption(key, not ns.db[key])
        self:SetChecked(ns.db[key] and true or false)
        ns.RefreshOptions()
    end)
    updaters[#updaters + 1] = function() c:SetChecked(ns.db[key] and true or false) end
    ns.optControls[key] = c
    return y - 22
end

buildDisplayOptions = function()
    local C = ns.optControls
    local y = -40
    y = rheader("Layout", y)
    C.layout, y = button(y, function() ns.SetOption("layout", LAYOUT_NEXT[ns.db.layout] or "list") end)
    updaters[#updaters + 1] = function() C.layout:SetText("Layout: " .. (LAYOUT_NAMES[ns.db.layout] or "?")) end

    y = rheader("Size and spacing", y - 4)
    y = stepper("scale", "Scale", 0.05, 0.4, 4, "%.2f", y)
    y = stepper("iconSize", "Icon size", 2, 10, 48, "%d", y)
    y = stepper("spacing", "Row spacing", 1, 0, 12, "%d", y)
    y = stepper("fontSize", "Font size", 1, 8, 24, "%d", y)
    y = checkbox("growUp", "Grow upwards", y)

    y = rheader("Look", y - 4)
    y = checkbox("showBg", "Background", y)
    y = stepper("bgAlpha", "Background opacity", 0.1, 0, 1, "%.1f", y)
    y = checkbox("showBorder", "Border", y)
    y = checkbox("redEdge", "Red edge on missing icons", y)
    C.headerColor, y = button(y, function()
        local list, nextId = ns.HEADER_COLORS, nil
        for i, c in ipairs(list) do
            if c.id == ns.db.headerColor then nextId = list[i % #list + 1].id end
        end
        ns.SetOption("headerColor", nextId or list[1].id)
    end)
    updaters[#updaters + 1] = function()
        local name = "Gold"
        for _, c in ipairs(ns.HEADER_COLORS) do if c.id == ns.db.headerColor then name = c.name end end
        C.headerColor:SetText("Header colour: " .. name)
    end

    y = rheader("Grouping", y - 4)
    y = checkbox("showWho", "Show who in the party misses a group buff", y)
    local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", panel, "TOPLEFT", RIGHT_X + 10, y)
    note:SetWidth(270)
    note:SetJustifyH("LEFT")
    note:SetText("Party buffs are read out of combat only. Pick Self/Group/Optional per buff on the left; click a group header in the list to collapse it.")
    y = y - 30

    y = rheader("When to show", y - 4)
    y = checkbox("showInCombat", "Show in combat", y)
    y = checkbox("onlyInGroup", "Only in a group or raid", y)
    C.whenNone, y = button(y, function()
        ns.SetOption("whenNone", ns.db.whenNone == "hide" and "fade" or "hide")
    end)
    updaters[#updaters + 1] = function()
        C.whenNone:SetText("Nothing missing: " .. (ns.db.whenNone == "fade" and "Fade" or "Hide"))
    end
    C.lock = panel.unlock
    panel.rightHeight = -y + 20
end

function ns.UpdateDisplayOptions()
    for _, u in ipairs(updaters) do u() end
end

local function build()
    -- standard WoW window (gold-trimmed frame, title bar, inset); falls back to a plain box
    local ok, f = pcall(CreateFrame, "Frame", "MissingBuffWarningOptions", UIParent, "BasicFrameTemplateWithInset")
    if ok and f then
        panel = f
        if panel.TitleText and panel.TitleText.SetText then
            panel.TitleText:SetText("Missing Buff Warning")
        end
    else
        panel = CreateFrame("Frame", "MissingBuffWarningOptions", UIParent, "BackdropTemplate")
        panel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        panel:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", panel, "TOP", 0, -12)
        title:SetText("Missing Buff Warning")
        local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
    end
    panel:SetSize(FULL_W, 360)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)

    panel.none = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.none:Hide()

    panel.edit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.edit:SetSize(200, 22)
    panel.edit:SetAutoFocus(false)
    panel.edit:SetScript("OnEnterPressed", addManual)
    panel.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.hint:SetText("Click the box, then shift-click a spell in your spellbook.")

    panel.add = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.add:SetSize(70, 22)
    panel.add:SetText("Add")
    panel.add:SetScript("OnClick", addManual)

    panel.unlock = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.unlock:SetSize(150, 24)
    panel.unlock:SetScript("OnClick", function()
        ns.SetLocked(not ns.db.locked)
        ns.RefreshOptions()
    end)

    panel.reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.reset:SetSize(130, 24)
    panel.reset:SetText("Reset size/position")
    panel.reset:SetScript("OnClick", function() ns.ResetLayout(); ns.RefreshOptions() end)

    panel.scaleText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

    ns.OnScaleChanged = function(sc)
        if panel:IsShown() then
            panel.scaleText:SetText(("Scale: %.2f"):format(sc))
            ns.UpdateDisplayOptions()
        end
    end
    buildDisplayOptions()

    tinsert(UISpecialFrames, "MissingBuffWarningOptions")
    panel:Hide()
end

-- Shift-click a spell in the spellbook while the "add" box has focus: that spell is added.
-- (Same hook other addons use: the game calls the chat link-insert function on shift-click.)
local lastText, lastTime
local function onInsertLink(text, label)
    if ns.linkDebug then   -- /mbw linkdebug: show every link the game tries to insert
        local focus = panel and panel.edit and panel.edit:HasFocus()
        print(("|cffffd200MBW linkdebug|r via %s: %s | addBoxFocus=%s"):format(
            tostring(label), (tostring(text):gsub("|", "||")), tostring(focus)))
    end
    if type(text) ~= "string" then return end
    if not (panel and panel.edit and panel.edit:IsVisible() and panel.edit:HasFocus()) then return end
    local id = text:match("|Hspell:(%d+)")
    if not id then return end                    -- only spell links; items etc. are ignored
    local now = GetTime()
    if text == lastText and lastTime and now - lastTime < 0.2 then return end  -- two hooks, one click
    lastText, lastTime = text, now
    -- use the spell's real name (not "Name(Rank 1)" / "Name (Racial Passive)" from the link text)
    local realName = ns.ResolveSpell(tonumber(id))
    local linkName = text:match("|h%[(.-)%]|h")
    local plain = linkName and (string.gsub(linkName, "%s*%b()", "")) or nil
    panel.edit:SetText(realName or ((plain and plain ~= "") and plain or id))
    addManual()
end
ns.linkHooks = {}
-- each hook is installed on its own, so one failing cannot disable the other
local ok1 = pcall(function()
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", function(t) onInsertLink(t, "ChatFrameUtil.InsertLink") end)
        ns.linkHooks[#ns.linkHooks + 1] = "ChatFrameUtil.InsertLink"
    end
end)
local ok2 = pcall(function()
    if ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(t) onInsertLink(t, "ChatEdit_InsertLink") end)
        ns.linkHooks[#ns.linkHooks + 1] = "ChatEdit_InsertLink"
    end
end)

-- Entry in Game Menu > Options > AddOns that opens the real panel
local function registerCategory()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local canvas = CreateFrame("Frame")
    canvas.name = "Missing Buff Warning"
    local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Missing Buff Warning")
    local blurb = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    blurb:SetWidth(520)
    blurb:SetJustifyH("LEFT")
    blurb:SetText("Flashes a big icon and text when one of your class buffs is missing (out of combat).\nCommands: /mbw  -  /mbw unlock  -  /mbw lock  -  /mbw reset  -  /mbw debug")
    local btn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    btn:SetSize(220, 26)
    btn:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -16)
    btn:SetText("Open buff settings")
    btn:SetScript("OnClick", function()
        if HideUIPanel and SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if not (panel and panel:IsShown()) then ns.ToggleOptions() end
    end)
    local category = Settings.RegisterCanvasLayoutCategory(canvas, "Missing Buff Warning")
    Settings.RegisterAddOnCategory(category)
end
local okCat, errCat = pcall(registerCategory)
if not okCat and geterrorhandler then geterrorhandler()(errCat) end

function ns.ToggleOptions()
    if not panel then build() end
    if panel:IsShown() then
        panel:Hide()
    else
        ns.RefreshOptions()
        panel:Show()
    end
end
