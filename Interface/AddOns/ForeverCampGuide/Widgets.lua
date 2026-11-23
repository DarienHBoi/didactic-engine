-- ForeverCampGuide - Widgets.lua
-- "Lienzo" con widgets reutilizables: cada página se vuelve a dibujar de arriba abajo
-- cuando cambian tus datos (habilidad, bolsas, recetas) sin crear marcos nuevos cada vez.
local _, ns = ...
local L = ns.T
local W = {}
ns.W = W

W.GOLD, W.WHITE, W.GREY, W.GREEN, W.RED, W.BLUE, W.ORANGE =
    "|cffffd100", "|cffffffff", "|cff9d9d9d", "|cff40ff40", "|cffff6060", "|cff66aaff", "|cffff9933"
W.READY     = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
W.NOT_READY = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t"
W.WAITING   = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14:14|t"
W.PIN       = "|TInterface\\Minimap\\Tracking\\Mailbox:0|t"

function W.Icon(path, size)
    return ("|T%s:%d:%d|t"):format(tostring(path), size or 16, size or 16)
end

function W.FactionColor(f)
    return (f == "H" and "|cffff5a4a") or (f == "A" and "|cff4aa3ff") or "|cffffd100"
end

------------------------------------------------------------------------
-- Creación de widgets base
------------------------------------------------------------------------
local function IconOnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local ok = false
    if self.kind == "item" then
        ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.id)
    elseif self.kind == "spell" then
        ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.id)
    end
    if not ok or GameTooltip:NumLines() == 0 then GameTooltip:SetText(self.fallbackName or "?") end
    if self.extraTip then GameTooltip:AddLine(self.extraTip, 0.8, 0.8, 0.8, true) end
    GameTooltip:AddLine(L("Mayús+clic: enlazar en el chat"), 0.55, 0.55, 0.55)
    GameTooltip:Show()
end

local function IconOnClick(self, button)
    if IsModifiedClick and IsModifiedClick("CHATLINK") then
        if self.kind == "item" then ns.InsertLink(ns.GetItemLink(self.id))
        elseif self.kind == "spell" then ns.InsertLink(ns.GetSpellLink(self.id)) end
        return
    end
    if self.onClick then self.onClick(self, button) end
end

local function CreateIconButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", IconOnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", IconOnClick)
    b:RegisterForClicks("AnyUp")
    return b
end

local function LinkOnEnter(self)
    self.text:SetTextColor(1, 1, 1)
    if self.tip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if type(self.tip) == "function" then self.tip(GameTooltip) else GameTooltip:SetText(self.tip, 1, 1, 1, 1, true) end
        GameTooltip:Show()
    end
end
local function LinkOnLeave(self)
    self.text:SetTextColor(self.r, self.g, self.b)
    GameTooltip:Hide()
end

local function CreateLink(parent)
    local b = CreateFrame("Button", nil, parent)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("LEFT")
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetHeight(1)
    b.line:SetPoint("BOTTOMLEFT", 0, 1); b.line:SetPoint("BOTTOMRIGHT", 0, 1)
    b:SetScript("OnEnter", LinkOnEnter)
    b:SetScript("OnLeave", LinkOnLeave)
    b:SetScript("OnClick", function(self, button) if self.onClick then self.onClick(self, button) end end)
    b:RegisterForClicks("AnyUp")
    return b
end

local function CreatePushButton(parent)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetScript("OnClick", function(self, button) if self.onClick then self.onClick(self, button) end end)
    b:SetScript("OnEnter", function(self)
        if self.tip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.tip, 1, 1, 1, 1, true); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function CreateCheck(parent)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    c:SetScript("OnClick", function(self) if self.onClick then self.onClick(self, self:GetChecked() and true or false) end end)
    return c
end

------------------------------------------------------------------------
-- Lienzo
------------------------------------------------------------------------
local Canvas = {}
Canvas.__index = Canvas

function W.NewCanvas(parent, width)
    local c = setmetatable({}, Canvas)
    c.frame = CreateFrame("Frame", nil, parent)
    c.frame:SetSize(width, 10)
    c.width = width
    c.pools, c.used = {}, {}
    c.y = 0
    return c
end

function Canvas:Acquire(kind, create)
    local pool = self.pools[kind]
    if not pool then pool = {}; self.pools[kind] = pool; self.used[kind] = 0 end
    local n = self.used[kind] + 1
    self.used[kind] = n
    local w = pool[n]
    if not w then w = create(self.frame); pool[n] = w end
    w:ClearAllPoints()
    w:Show()
    return w
end

function Canvas:Reset()
    for kind, pool in pairs(self.pools) do
        for _, w in ipairs(pool) do w:Hide() end
        self.used[kind] = 0
    end
    self.y = -6
end

function Canvas:Finish()
    self.frame:SetHeight(math.max(-self.y + 20, 20))
end

-- Texto. o = { font, x, y, width, gap, noAdvance, justify }
function Canvas:Text(text, o)
    o = o or {}
    local fs = self:Acquire("fs", function(f) return f:CreateFontString(nil, "OVERLAY") end)
    fs:SetFontObject(o.font or "GameFontHighlight")
    fs:SetJustifyH(o.justify or "LEFT")
    fs:SetJustifyV("TOP")
    local x = o.x or 0
    fs:SetWidth(o.width or (self.width - x - 6))
    fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, o.y or self.y)
    fs:SetText(text or "")
    if not o.noAdvance then self.y = self.y - fs:GetStringHeight() - (o.gap or 4) end
    return fs
end

function Canvas:Header(text) return self:Text(text, { font = "GameFontNormalLarge", gap = 8 }) end
function Canvas:SubHeader(text, x) return self:Text(text, { font = "GameFontNormal", gap = 5, x = x }) end
function Canvas:Small(text, x, gap) return self:Text(text, { font = "GameFontHighlightSmall", x = x, gap = gap }) end
function Canvas:Bullet(text, x) return self:Text(W.GOLD .. "•|r " .. text, { x = (x or 0) + 6, gap = 4 }) end
function Canvas:Space(h) self.y = self.y - (h or 6) end

function Canvas:Rect(x, y, w, h, r, g, b, a, layer)
    local t = self:Acquire("tex", function(f) return f:CreateTexture(nil, "BACKGROUND") end)
    t:SetDrawLayer(layer or "BACKGROUND")
    t:SetColorTexture(r, g, b, a)
    t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
    t:SetSize(math.max(w, 1), math.max(h, 1))
    return t
end

function Canvas:Separator()
    self:Rect(0, self.y - 4, self.width - 6, 1, 1, 0.82, 0, 0.3, "ARTWORK")
    self.y = self.y - 14
end

-- Fondo de tarjeta: se llama al final con la y inicial
function Canvas:CardBackground(x, startY, endY, accent)
    local h = startY - endY
    self:Rect(x, startY, self.width - x - 6, h, 0, 0, 0, 0.35, "BACKGROUND")
    local r, g, b = 0.45, 0.45, 0.45
    if accent == "current" then r, g, b = 1, 0.82, 0
    elseif accent == "done" then r, g, b = 0.25, 0.8, 0.25
    elseif accent == "warn" then r, g, b = 0.9, 0.35, 0.3 end
    self:Rect(x, startY, 3, h, r, g, b, 0.9, "BORDER")
end

function Canvas:IconButton(x, y, size, kind, id, texture, fallbackName, onClick, extraTip)
    local b = self:Acquire("icon", CreateIconButton)
    b:SetSize(size, size)
    b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
    b.kind, b.id, b.fallbackName, b.onClick, b.extraTip = kind, id, fallbackName, onClick, extraTip
    b.icon:SetTexture(texture or 134400)
    b.icon:SetDesaturated(false)
    b.count:SetText("")
    return b
end

-- Enlace de texto clicable. Devuelve el botón (su ancho = ancho del texto)
function Canvas:Link(x, y, text, onClick, tip, font, color)
    local b = self:Acquire("link", CreateLink)
    b.text:SetFontObject(font or "GameFontNormal")
    b.text:SetText(text)
    local r, g, bb = 1, 0.82, 0
    if color then r, g, bb = color[1], color[2], color[3] end
    b.r, b.g, b.b = r, g, bb
    b.text:SetTextColor(r, g, bb)
    b.line:SetColorTexture(r, g, bb, 0.5)
    b:SetSize(b.text:GetStringWidth() + 2, b.text:GetStringHeight() + 3)
    b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
    b.onClick, b.tip = onClick, tip
    return b
end

function Canvas:Button(x, y, w, text, onClick, tip, h)
    local b = self:Acquire("push", CreatePushButton)
    b:SetSize(w, h or 22)
    b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
    b:SetText(text)
    b:Enable()
    b.onClick, b.tip = onClick, tip
    return b
end

function Canvas:Check(x, y, checked, onClick)
    local c = self:Acquire("check", CreateCheck)
    c:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
    c:SetChecked(checked and true or false)
    c.onClick = onClick
    return c
end

------------------------------------------------------------------------
-- Flujo horizontal: coloca elementos uno tras otro y salta de línea si no caben
------------------------------------------------------------------------
local Flow = {}
Flow.__index = Flow

function Canvas:BeginFlow(x, lineHeight)
    return setmetatable({ c = self, x0 = x or 0, x = x or 0, y = self.y, lh = lineHeight or 18, maxX = self.width - 8 }, Flow)
end

function Flow:Fit(w)
    if self.x + w > self.maxX and self.x > self.x0 then
        self.x = self.x0
        self.y = self.y - self.lh
    end
end

function Flow:Text(text, font)
    local fs = self.c:Text(text, { font = font or "GameFontHighlightSmall", x = self.x, y = self.y - 2, width = 1000, noAdvance = true })
    local w = fs:GetStringWidth() + 6
    if self.x + w > self.maxX and self.x > self.x0 then
        self.x = self.x0
        self.y = self.y - self.lh
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", self.c.frame, "TOPLEFT", self.x, self.y - 2)
    end
    fs:SetWidth(w)
    self.x = self.x + w
    return fs
end

function Flow:Icon(size, kind, id, texture, fallbackName, onClick, extraTip)
    self:Fit(size + 3)
    local b = self.c:IconButton(self.x, self.y, size, kind, id, texture, fallbackName, onClick, extraTip)
    self.x = self.x + size + 3
    return b
end

function Flow:Link(text, onClick, tip, font, color)
    local b = self.c:Link(self.x, self.y - 1, text, onClick, tip, font, color)
    local w = b:GetWidth() + 8
    if self.x + w > self.maxX and self.x > self.x0 then
        self.x = self.x0
        self.y = self.y - self.lh
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.c.frame, "TOPLEFT", self.x, self.y - 1)
    end
    self.x = self.x + w
    return b
end

function Flow:Button(w, text, onClick, tip)
    self:Fit(w + 4)
    local b = self.c:Button(self.x, self.y + 2, w, text, onClick, tip, 20)
    self.x = self.x + w + 4
    return b
end

function Flow:NewLine()
    self.x = self.x0
    self.y = self.y - self.lh
end

function Flow:End(gap)
    self.c.y = self.y - self.lh - (gap or 2)
end
