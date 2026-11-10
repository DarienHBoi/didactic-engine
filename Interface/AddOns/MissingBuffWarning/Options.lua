local ADDON, ns = ...

local panel
local rows = {}   -- pooled row frames
local WIDTH = 340

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
    r.label:SetWidth(WIDTH - 110)
    r.label:SetJustifyH("LEFT")
    r.del = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    r.del:SetSize(22, 22)
    r.del:SetFrameLevel(panel:GetFrameLevel() + 5)
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

function ns.RefreshOptions()
    if not panel then return end
    local class = ns.PlayerClass()
    local cfg = ns.ClassConfig(class)
    for _, r in ipairs(rows) do r.bg:Hide(); r.check:Hide(); r.label:Hide(); r.del:Hide() end
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
    panel.footer:SetPoint("TOP", panel, "TOP", 0, y)
    panel.footer:SetText(idx .. " buffs listed")
    panel:SetHeight(-y + 28)
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
    panel:SetSize(WIDTH, 360)
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
        if panel:IsShown() then panel.scaleText:SetText(("Scale: %.2f"):format(sc)) end
    end

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
