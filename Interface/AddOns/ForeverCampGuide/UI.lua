-- ForeverCampGuide - UI.lua
local _, ns = ...
local L = ns.T
local W, P = ns.W, ns.P
local GOLD, WHITE, GREY, GREEN, ORANGE = W.GOLD, W.WHITE, W.GREY, W.GREEN, W.ORANGE

local FRAME_W, FRAME_H = 900, 620
local NAV_W = 196
local CONTENT_W = FRAME_W - 16 - NAV_W - 12 - 40

local frame, scroll, canvas, headerTitle, headerSkill, headerNext, tabBar
local navButtons, tabButtons = {}, {}
local current = { key = nil, tab = nil }
local ctx = {}

------------------------------------------------------------------------
-- Definición de páginas
------------------------------------------------------------------------
local GENERAL = {
    howto     = { label = "Cómo funciona", icon = "fire", build = P.HowTo },
    first     = { label = "Tu primer campamento", icon = "Interface\\Icons\\INV_Misc_Map_01", build = P.First },
    campfires = { label = "Fogatas", icon = "fire", build = P.Campfires },
    forever   = { label = "Novedades de Forever", icon = "Interface\\Icons\\INV_Misc_Note_01", build = P.Forever },
    merchant  = { label = "Favor del mercader", icon = "Interface\\Icons\\INV_Misc_Coin_17", build = P.Merchant },
    fishcook  = { label = "Pesca + Cocina", icon = "Interface\\Icons\\INV_Misc_Fish_02", build = P.ComboTab },
    misc      = { label = "Misceláneos", icon = "Interface\\Icons\\INV_Misc_Bag_10", build = P.Misc },
    options   = { label = "Opciones", icon = "Interface\\Icons\\INV_Misc_Gear_01", build = P.Options },
}

local function ProfessionTabs(prof)
    local tabs = {}
    if ns.guides[prof.key] then
        tabs[#tabs + 1] = { key = "guide", label = L("Subir 1-300"), build = P.GuideTab }
        tabs[#tabs + 1] = { key = "trainers", label = L("Instructores"), build = P.TrainersTab }
        local g = ns.guides[prof.key]
        if g.shopping or not g.gather then
            tabs[#tabs + 1] = { key = "shopping", label = L("Compras"), build = P.ShoppingTab }
        end
        if not g.noRecipes then
            tabs[#tabs + 1] = { key = "recipes", label = L("Recetas"), build = P.RecipesTab }
        end
    end
    tabs[#tabs + 1] = { key = "camp", label = L("Campamento"), build = P.CampTab }
    if prof.key == "fishing" or prof.key == "cooking" then
        tabs[#tabs + 1] = { key = "combo", label = L("Pesca + Cocina"), build = function(c) P.ComboTab(c) end }
    end
    return tabs
end

------------------------------------------------------------------------
-- Cabecera
------------------------------------------------------------------------
local function UpdateHeader()
    local key = current.key
    local prof = ns.profByKey[key]
    if prof then
        headerTitle:SetText(W.Icon(ns.ICON_PATH .. prof.icon, 24) .. "  " .. ns.ProfName(prof))
        local skill, max = ns.GetProfessionSkill(prof)
        if skill then
            local rn = ns.RankName(max)
            headerSkill:SetText((L("Tu habilidad: %s%d|r / %s%s")):format(WHITE, skill, tostring(max or "?"), rn and (GREY .. "  (" .. rn .. ")|r") or ""))
        else
            headerSkill:SetText(GREY .. L("No conoces esta profesión (o no se pudo leer tu habilidad).|r"))
        end
        local text = ""
        if ns.guides[key] then
            local cap = ns.CapWarning(skill, max)
            if cap then
                text = ORANGE .. cap .. "|r"
            elseif skill then
                local e = ns.CurrentStep(key, skill)
                if e then
                    local s = e.step
                    local left, total = ns.StepRemaining(s, skill)
                    local count = left and (left .. "x ") or ""
                    if left and total and left < total then count = (L("%d de %d: ")):format(left, total) end
                    text = GOLD .. L("Paso actual [") .. s.r .. "]:|r " .. WHITE .. (s.spell and (count .. ns.GetSpellName(s.spell, s.name)) or L(s.short or s.text or "")) .. "|r"
                    if s.spell then text = text .. "  " .. P.KnownIcon(s.spell) end
                else
                    text = GREEN .. L("Has completado la guía.") .. "|r"
                end
            else
                text = GREY .. L("Aprende la profesión con un instructor (pestaña Instructores).|r")
            end
        else
            text = GREY .. L("La web no tiene guía de subida de Forever para esta profesión: aquí tienes su información de campamento.|r")
        end
        headerNext:SetText(text)
    else
        local def = GENERAL[key]
        headerTitle:SetText(def and L(def.label) or "")
        headerSkill:SetText(GREY .. L("Guía de profesiones y campamento de WoW Forever|r"))
        headerNext:SetText("")
    end
end

------------------------------------------------------------------------
-- Pestañas
------------------------------------------------------------------------
local function TabButton(i)
    local b = tabButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, tabBar, "UIPanelButtonTemplate")
    b:SetHeight(22)
    b:SetScript("OnClick", function(self) ns.ShowPage(current.key, self.tabKey) end)
    tabButtons[i] = b
    return b
end

local function BuildTabs(tabs)
    local x = 0
    for i, t in ipairs(tabs or {}) do
        local b = TabButton(i)
        b.tabKey = t.key
        b:SetText(t.label)
        b:SetWidth(math.max(90, #t.label * 7 + 20))
        b:ClearAllPoints()
        b:SetPoint("LEFT", tabBar, "LEFT", x, 0)
        x = x + b:GetWidth() + 4
        if t.key == current.tab then b:Disable() else b:Enable() end
        b:Show()
    end
    for i = #(tabs or {}) + 1, #tabButtons do tabButtons[i]:Hide() end
end

------------------------------------------------------------------------
-- Navegación lateral
------------------------------------------------------------------------
local function RefreshNav()
    for _, b in ipairs(navButtons) do
        b.sel:SetShown(b.key == current.key)
        if b.prof then
            local rank = ns.GetProfessionSkill(b.prof)
            b.right:SetText(rank and (WHITE .. rank .. "|r") or "")
            b.text:SetFontObject(rank and "GameFontNormal" or "GameFontDisable")
        end
    end
end

local function NavButton(parent, key, label, icon, y, prof)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(NAV_W - 12, 21)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    b.key, b.prof = key, prof
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints(); b.sel:SetColorTexture(1, 0.82, 0, 0.2); b.sel:Hide()
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetSize(17, 17); ic:SetPoint("LEFT", 3, 0); ic:SetTexture(icon)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("LEFT", ic, "RIGHT", 6, 0)
    b.text:SetText(label)
    b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.right:SetPoint("RIGHT", -4, 0)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:SetScript("OnClick", function() ns.ShowPage(key) end)
    navButtons[#navButtons + 1] = b
end

local function NavLabel(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    fs:SetText(text)
end

------------------------------------------------------------------------
-- Ventana
------------------------------------------------------------------------
local function Create()
    local backdrop = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "ForeverCampGuideFrame", UIParent, backdrop)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true); frame:SetClampedToScreen(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    end
    tinsert(UISpecialFrames, "ForeverCampGuideFrame")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local logo = frame:CreateTexture(nil, "OVERLAY")
    logo:SetSize(26, 26); logo:SetPoint("TOPLEFT", 16, -10)
    logo:SetTexture(ns.LOGO)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    title:SetText(GREY .. "Forever Camp Guide|r")

    -- Navegación
    local nav = CreateFrame("Frame", nil, frame, backdrop)
    nav:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -40)
    nav:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
    nav:SetWidth(NAV_W)
    if nav.SetBackdrop then
        nav:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        nav:SetBackdropColor(0, 0, 0, 0.45)
        nav:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    end
    local fire = ns.GetItemIcon(ns.campfires[1].item, ns.CAMPFIRE_ICON)
    local y = -8
    NavLabel(nav, L("CAMPAMENTO"), y); y = y - 15
    for _, k in ipairs({ "howto", "first", "campfires" }) do
        local d = GENERAL[k]
        NavButton(nav, k, L(d.label), d.icon == "fire" and fire or d.icon, y); y = y - 21
    end
    y = y - 5
    NavLabel(nav, L("PROFESIONES"), y); y = y - 15
    for _, prof in ipairs(ns.professions) do
        NavButton(nav, prof.key, ns.ProfName(prof), ns.ICON_PATH .. prof.icon, y, prof); y = y - 21
    end
    y = y - 5
    NavLabel(nav, L("MÁS"), y); y = y - 15
    for _, k in ipairs({ "merchant", "fishcook", "misc", "forever", "options" }) do
        local d = GENERAL[k]
        NavButton(nav, k, L(d.label), d.icon, y); y = y - 21
    end
    local mapBtn = CreateFrame("Button", nil, nav, "UIPanelButtonTemplate")
    mapBtn:SetSize(NAV_W - 16, 22)
    mapBtn:SetPoint("BOTTOM", nav, "BOTTOM", 0, 8)
    mapBtn:SetText(L("Abrir mapa"))
    mapBtn:SetScript("OnClick", function() ns.Map.ShowZone(nil) end)

    -- Cabecera
    local hx = 16 + NAV_W + 14
    headerTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headerTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", hx, -38)
    headerTitle:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
    headerTitle:SetJustifyH("LEFT")
    headerSkill = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerSkill:SetPoint("TOPLEFT", headerTitle, "BOTTOMLEFT", 0, -5)
    headerSkill:SetPoint("RIGHT", frame, "RIGHT", -30, 0)
    headerSkill:SetJustifyH("LEFT")
    headerNext = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerNext:SetPoint("TOPLEFT", headerSkill, "BOTTOMLEFT", 0, -4)
    headerNext:SetPoint("RIGHT", frame, "RIGHT", -30, 0)
    headerNext:SetJustifyH("LEFT")
    headerNext:SetHeight(14)

    tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", frame, "TOPLEFT", hx, -104)
    tabBar:SetSize(CONTENT_W + 30, 24)

    -- Contenido
    scroll = CreateFrame("ScrollFrame", "ForeverCampGuideScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", hx, -134)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 20)
    canvas = W.NewCanvas(scroll, CONTENT_W)
    scroll:SetScrollChild(canvas.frame)

    frame:SetScript("OnShow", function() ns.RefreshCurrent() end)
    frame:Hide()
end

------------------------------------------------------------------------
-- Dibujo
------------------------------------------------------------------------
local function Render(keepScroll)
    local key = current.key
    local prof = ns.profByKey[key]
    wipe(ctx)
    if prof then
        ctx.prof, ctx.guideKey, ctx.guide = prof, key, ns.guides[key]
        ctx.skill, ctx.max = ns.GetProfessionSkill(prof)
        if ctx.guide then ctx.current = ns.CurrentStep(key, ctx.skill); ctx.current = ctx.current and ctx.current.step end
    end
    local old = keepScroll and scroll:GetVerticalScroll() or 0
    canvas:Reset()
    local builder
    if prof then
        local tabs = ProfessionTabs(prof)
        local found
        for _, t in ipairs(tabs) do if t.key == current.tab then found = t end end
        found = found or tabs[1]
        current.tab = found.key
        BuildTabs(tabs)
        tabBar:Show()
        builder = found.build
    else
        tabBar:Hide()
        builder = GENERAL[key].build
    end
    local ok, err = pcall(builder, canvas, ctx)
    if not ok then
        canvas:Text(L("|cffff6060Error al dibujar la página:|r ") .. tostring(err), { gap = 6 })
        ns.lastError = (current.key or "?") .. "/" .. tostring(current.tab) .. ": " .. tostring(err)
        if geterrorhandler then geterrorhandler()(err) end
    end
    canvas:Finish()
    UpdateHeader()
    RefreshNav()
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    local maxScroll = math.max(0, canvas.frame:GetHeight() - scroll:GetHeight())
    scroll:SetVerticalScroll(math.min(old, maxScroll))
end

function ns.ScrollToCurrent()
    if not (frame and ctx.currentY) then return end
    local maxScroll = math.max(0, canvas.frame:GetHeight() - scroll:GetHeight())
    scroll:SetVerticalScroll(math.max(0, math.min(-ctx.currentY - 10, maxScroll)))
end

function ns.RefreshCurrent()
    if not frame or not frame:IsShown() or not current.key then return end
    Render(true)
end

function ns.ShowPage(key, tab)
    if not (GENERAL[key] or ns.profByKey[key]) then key = "howto" end
    if not frame then Create() end
    local changed = key ~= current.key or (tab and tab ~= current.tab)
    current.key = key
    current.tab = tab or (ns.db and ns.db.lastTab[key]) or nil
    frame:Show()
    Render(not changed)
    if ns.db then
        ns.db.lastPage = key
        if current.tab then ns.db.lastTab[key] = current.tab end
    end
    if changed and current.tab == "guide" then ns.ScrollToCurrent() end
end

function ns.Toggle()
    if frame and frame:IsShown() then frame:Hide()
    else ns.ShowPage(ns.db and ns.db.lastPage or "howto") end
end
