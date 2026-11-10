local _, S = ...
S.UI = S.UI or {}

S.UI.GOLD = { 1, 0.82, 0 }
S.UI.QUESTION = 134400 -- inv_misc_questionmark

S.UI.TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

-- Dark fill + Blizzard tooltip border, the same recipe the Dungeon Journal uses. False when backdrops are unavailable.
function S.UI.backdrop(f, edge, inset)
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
function S.UI.button(parent, text, w, h, primary)
    local b = CreateFrame("Button", nil, parent, S.UI.TEMPLATE)
    b:SetSize(w, h or 28)
    local hasBackdrop = S.UI.backdrop(b, 12, 4)
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
        elseif primary then bg, border, tc = BTN.pbg, BTN.pborder, BTN.ptext end
        if hasBackdrop then
            self:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            self:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
        else
            self.flat:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
        end
        self.label:SetTextColor(tc[1], tc[2], tc[3])
    end
    local baseEnable = b.SetEnabled
    b.SetEnabled = function(self, v) baseEnable(self, v); paint(self, v and true or false) end
    b.SetText = function(self, t) self.label:SetText(t or "") end
    b:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    b:SetText(text)
    paint(b, true)
    return b
end

-- Dark panel with the Blizzard tooltip border; falls back to flat textures with a thin gold edge.
function S.UI.panel(parent)
    local p = CreateFrame("Frame", nil, parent, S.UI.TEMPLATE)
    if S.UI.backdrop(p, 12, 3) then
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
function S.UI.itemIcon(id)
    local fn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if fn and id then
        local ok, icon = pcall(fn, id)
        if ok and icon then return icon end
    end
    return S.UI.QUESTION
end

function S.UI.scrollList(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    return scroll, content
end

-- Signed copper text: "-1g 20s" for a loss, "unknown" for nil.
function S.UI.signedMoney(copper)
    if copper == nil then return "unknown" end
    if copper < 0 then return "-" .. S.Money.format(-copper) end
    return S.Money.format(copper)
end
