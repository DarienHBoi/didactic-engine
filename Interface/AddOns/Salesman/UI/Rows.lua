local _, S = ...
S.UI = S.UI or {}

S.UI.CAT_W, S.UI.CAT_H = 156, 34
S.UI.ENCH_W, S.UI.ENCH_H = 222, 54
S.UI.REAG_W, S.UI.REAG_H = 376, 22

local SELECT_TEX = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"

-- Card look: dark fill, Blizzard border, gold line on top; SetSelected swaps in the gold border.
local function selection(btn)
    local hasBackdrop = S.UI.backdrop(btn, 10, 3)
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

S.UI.cardStyle = selection

-- Left pane entry: icon, category name, count.
function S.UI.newCategory(parent)
    local b = CreateFrame("Button", nil, parent, S.UI.TEMPLATE)
    b:SetSize(S.UI.CAT_W, S.UI.CAT_H)
    selection(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22)
    b.icon:SetPoint("LEFT", 4, 0)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.label:SetWidth(96)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.count:SetPoint("RIGHT", -4, 0)
    return b
end

-- Middle pane entry: icon, enchant name, mats and ask line, favourite star.
function S.UI.newEnchant(parent)
    local b = CreateFrame("Button", nil, parent, S.UI.TEMPLATE)
    b:SetSize(S.UI.ENCH_W, S.UI.ENCH_H)
    selection(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(40, 40)
    b.icon:SetPoint("LEFT", 8, 0)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -1)
    b.name:SetTextColor(1, 0.88, 0.24)
    b.name:SetShadowColor(0, 0, 0, 1)
    b.name:SetShadowOffset(1, -1)
    b.name:SetWidth(140)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    -- How many you can make now: a count on the icon like an item stack; the icon greys out when mats are missing.
    b.stock = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.stock:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -2, 2)
    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, 1)
    b.sub:SetJustifyH("LEFT")
    b.pick = CreateFrame("CheckButton", nil, b, "UICheckButtonTemplate")
    b.pick:SetSize(22, 22)
    b.pick:SetPoint("BOTTOMRIGHT", -4, 4)
    b.star = CreateFrame("Button", nil, b)
    b.star:SetSize(20, 20)
    b.star:SetPoint("TOPRIGHT", -6, -6)
    b.star.label = b.star:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.star.label:SetPoint("CENTER", 0, -3)
    b.star.label:SetText("*")
    return b
end

-- Detail pane reagent line: icon (hover = item tooltip), name x count, each / line / stack prices.
function S.UI.newReagent(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(S.UI.REAG_W, S.UI.REAG_H)
    r.iconBtn = CreateFrame("Button", nil, r)
    r.iconBtn:SetSize(20, 20)
    r.iconBtn:SetPoint("LEFT", 12, 0)
    r.icon = r.iconBtn:CreateTexture(nil, "ARTWORK")
    r.icon:SetAllPoints()
    r.iconBtn:SetScript("OnEnter", function(self)
        if not r.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, r.itemID) end
        GameTooltip:Show()
    end)
    r.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local function col(x, w)
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    r.name = col(38, 150)
    r.unit = col(192, 60)
    r.line = col(256, 60)
    r.stack = col(320, 56)
    return r
end
