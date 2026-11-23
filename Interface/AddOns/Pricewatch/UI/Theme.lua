local _, P = ...
P.UI = P.UI or {}

P.UI.GOLD = { 1, 0.82, 0 }
P.UI.QUESTION = 134400 -- inv_misc_questionmark

P.UI.TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

-- Dark fill + Blizzard tooltip border, the same recipe the Dungeon Journal uses. False when backdrops are unavailable.
function P.UI.backdrop(f, edge, inset)
    if not f.SetBackdrop then return false end
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = edge or 12,
        insets = { left = inset or 3, right = inset or 3, top = inset or 3, bottom = inset or 3 },
    })
    return true
end

local BTN = {
    bg = { 0.12, 0.115, 0.105, 0.98 }, border = { 0.48, 0.40, 0.27, 1 }, text = { 1, 0.82, 0.27 },
    pbg = { 0.22, 0.165, 0.05, 0.98 }, pborder = { 0.9, 0.72, 0.22, 1 }, ptext = { 1, 0.9, 0.4 },
    dbg = { 0.08, 0.08, 0.075, 0.95 }, dborder = { 0.28, 0.26, 0.22, 1 }, dtext = { 0.5, 0.5, 0.5 },
}

-- Large dark/gold button in the Dungeon Journal style. primary = gold-accented main action.
-- Keeps the API the rest of the addon uses: SetText, SetEnabled, SetScript, RegisterForClicks, SetPoint.
function P.UI.button(parent, text, w, h, primary)
    local b = CreateFrame("Button", nil, parent, P.UI.TEMPLATE)
    b:SetSize(w, h or 28)
    local hasBackdrop = P.UI.backdrop(b, 12, 4)
    if not hasBackdrop then
        b.flat = b:CreateTexture(nil, "BACKGROUND")
        b.flat:SetAllPoints()
    end
    b.label = b:CreateFontString(nil, "OVERLAY", primary and "GameFontNormalLarge" or "GameFontHighlight")
    b.label:SetPoint("CENTER")
    b.label:SetShadowColor(0, 0, 0, 1)
    b.label:SetShadowOffset(1, -1)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local function paint(self, enabled)
        local bg, border, tc = BTN.bg, BTN.border, BTN.text
        if not enabled then bg, border, tc = BTN.dbg, BTN.dborder, BTN.dtext
        elseif primary or self.selected then bg, border, tc = BTN.pbg, BTN.pborder, BTN.ptext end
        if hasBackdrop then
            self:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            self:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
        else
            self.flat:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
        end
        self.label:SetTextColor(tc[1], tc[2], tc[3])
    end
    local baseEnable = b.SetEnabled
    b.enabledFlag = true
    b.SetEnabled = function(self, v) baseEnable(self, v); self.enabledFlag = v and true or false; paint(self, self.enabledFlag) end
    -- "Selected" look for a button that stays clickable (a tab, the chosen range): gold border and fill, text kept.
    b.SetSelected = function(self, on) self.selected = on and true or false; paint(self, self.enabledFlag) end
    b.SetText = function(self, t) self.label:SetText(t or "") end
    b:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    b:SetText(text)
    paint(b, true)
    return b
end

-- Dark panel with the Blizzard tooltip border; falls back to flat textures with a thin gold edge.
function P.UI.panel(parent)
    local p = CreateFrame("Frame", nil, parent, P.UI.TEMPLATE)
    if P.UI.backdrop(p, 12, 3) then
        p:SetBackdropColor(0.04, 0.04, 0.035, 0.95)
        p:SetBackdropBorderColor(0.34, 0.28, 0.18, 1)
        return p
    end
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    p.bg:SetColorTexture(0.05, 0.045, 0.04, 0.92)
    local function edge(a, b, w, h)
        local t = p:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.45, 0.36, 0.12, 1)
        t:SetPoint(a)
        t:SetPoint(b)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    return p
end

-- Item icon id, or the question mark when the item is not known to the client yet.
function P.UI.itemIcon(id)
    local fn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if fn and id then
        local ok, icon = pcall(fn, id)
        if ok and icon then return icon end
    end
    return P.UI.QUESTION
end

function P.UI.scrollList(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    return scroll, content
end

-- Signed copper text: "-1g 20s" for a loss, "unknown" for nil.
function P.UI.signedMoney(copper)
    if copper == nil then return "unknown" end
    if copper < 0 then return "-" .. P.Money.format(-copper) end
    return P.Money.format(copper)
end

-- Card look: dark fill, Blizzard border, gold line on top; SetSelected swaps in the gold border.
local function selection(btn)
    local hasBackdrop = P.UI.backdrop(btn, 10, 3)
    if hasBackdrop then
        btn:SetBackdropColor(0.02, 0.02, 0.02, 0.55)
        btn:SetBackdropBorderColor(0.34, 0.34, 0.34, 1)
    else
        btn.flat = btn:CreateTexture(nil, "BACKGROUND")
        btn.flat:SetAllPoints()
        btn.flat:SetColorTexture(0.06, 0.055, 0.045, 0.9)
    end
    local line = btn:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 4, -4)
    line:SetPoint("TOPRIGHT", -4, -4)
    line:SetHeight(1)
    line:SetColorTexture(1, 0.84, 0.25, 0.30)
    local h = btn:CreateTexture(nil, "HIGHLIGHT")
    h:SetPoint("TOPLEFT", 4, -4)
    h:SetPoint("BOTTOMRIGHT", -4, 4)
    h:SetColorTexture(1, 1, 1, 0.08)
    btn.SetSelected = function(self, on)
        if hasBackdrop then
            if on then
                self:SetBackdropColor(0.16, 0.12, 0.03, 0.85)
                self:SetBackdropBorderColor(1, 0.82, 0.27, 1)
            else
                self:SetBackdropColor(0.02, 0.02, 0.02, 0.55)
                self:SetBackdropBorderColor(0.34, 0.34, 0.34, 1)
            end
        else
            self.flat:SetColorTexture(on and 0.2 or 0.06, on and 0.15 or 0.055, on and 0.04 or 0.045, 0.9)
        end
    end
end

P.UI.cardStyle = selection
