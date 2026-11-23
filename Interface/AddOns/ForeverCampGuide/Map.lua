-- ForeverCampGuide - Map.lua
-- Visor de mapas dentro del addon: dibuja la imagen de la zona con las texturas del propio
-- juego y coloca sobre ella los PNJ de las guías (coordenadas de wow-professions.com) y tu posición.
local _, ns = ...
local L = ns.T
local W = ns.W
local Map = {}
ns.Map = Map

local MAP_W = 640
local frame, area, title, sub, info, playerDot, noMap, selLabel, selGlow
local tiles, pins = {}, {}
local btnWaypoint, btnWorld, btnSave, btnClear
local current = { mapID = nil, npc = nil, layerH = 0 }

local function PinOnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.npc.label and L(self.npc.label) or self.npc[3], 1, 0.82, 0)
    if self.npc[4] then GameTooltip:AddLine(L(self.npc[4]), 1, 1, 1, true) end
    local e = ns.npcIndex[self.npc[3]]
    if e then
        local profs = {}
        for pk in pairs(e.profs) do profs[#profs + 1] = ns.profByKey[pk] and ns.ProfName(ns.profByKey[pk]) or pk end
        table.sort(profs)
        GameTooltip:AddLine(table.concat(profs, ", "), 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine(L("Clic: seleccionar  ·  Clic derecho: marcador"), 0.55, 0.55, 0.55)
    GameTooltip:Show()
end

local function GetPin(i)
    local p = pins[i]
    if p then return p end
    p = CreateFrame("Button", nil, area)
    p:SetFrameLevel(area:GetFrameLevel() + 5)
    p.tex = p:CreateTexture(nil, "OVERLAY")
    p.tex:SetAllPoints()
    p:RegisterForClicks("AnyUp")
    p:SetScript("OnEnter", PinOnEnter)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local c = ns.GetCoords(self.npc[3])
            if c then ns.SetWaypoint(self.npc[3], c.m, c.x, c.y) end
        else
            Map.ShowNPC(self.npc)
        end
    end)
    pins[i] = p
    return p
end

local function CursorToMap()
    local left, top = area:GetLeft(), area:GetTop()
    if not left then return nil end
    local cx, cy = GetCursorPosition()
    local s = area:GetEffectiveScale()
    local x = (cx / s - left) / area:GetWidth()
    local y = (top - cy / s) / area:GetHeight()
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

local function Create()
    frame = CreateFrame("Frame", "ForeverCampGuideMapFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(MAP_W + 28, 560)
    frame:SetPoint("CENTER", 120, 0)
    frame:SetFrameStrata("DIALOG")
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
    tinsert(UISpecialFrames, "ForeverCampGuideMapFrame")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16); title:SetPoint("RIGHT", -36, 0); title:SetJustifyH("LEFT")
    sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4); sub:SetPoint("RIGHT", -20, 0); sub:SetJustifyH("LEFT")

    area = CreateFrame("Frame", nil, frame)
    area:SetPoint("TOPLEFT", 14, -62)
    area:SetSize(MAP_W, 420)
    if area.SetClipsChildren then area:SetClipsChildren(true) end
    area:EnableMouse(true)
    area:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and IsControlKeyDown() and current.npc and current.mapID then
            local x, y = CursorToMap()
            if x then
                ns.SaveCoords(current.npc[3], current.mapID, x, y, true, true)
                ns.Print((L("Ubicación de %s fijada a mano (%.1f, %.1f).")):format(current.npc[3], x * 100, y * 100))
                Map.Render()
                ns.RequestRefresh()
            end
        end
    end)
    local bg = area:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6)
    noMap = area:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    noMap:SetPoint("CENTER"); noMap:SetText(L("No se pudo cargar la imagen de esta zona en tu cliente."))

    selGlow = area:CreateTexture(nil, "OVERLAY")
    selGlow:SetTexture("Interface\\Cooldown\\star4")
    selGlow:SetBlendMode("ADD")
    selGlow:SetSize(46, 46)
    selGlow:SetVertexColor(1, 0.82, 0, 0.9)
    selLabel = area:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selLabel:SetShadowOffset(1, -1)

    playerDot = CreateFrame("Frame", nil, area)
    playerDot:SetSize(20, 20)
    playerDot:SetFrameLevel(area:GetFrameLevel() + 8)
    playerDot.tex = playerDot:CreateTexture(nil, "OVERLAY")
    playerDot.tex:SetAllPoints()
    playerDot.tex:SetTexture("Interface\\Minimap\\MinimapArrow")

    info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetJustifyH("LEFT"); info:SetJustifyV("TOP")

    local function MakeButton(text, w, onClick, tip)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(w, 22); b:SetText(text)
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    btnWaypoint = MakeButton(L("Poner marcador"), 130, function()
        local c = current.npc and ns.GetCoords(current.npc[3])
        if c then ns.SetWaypoint(current.npc[3], c.m, c.x, c.y) end
    end, L("Coloca un marcador en el mapa del juego (y en TomTom si lo tienes)."))
    btnWorld = MakeButton(L("Mapa del mundo"), 130, function()
        local c = current.npc and ns.GetCoords(current.npc[3])
        if c then ns.SetWaypoint(current.npc[3], c.m, c.x, c.y) end
        ns.OpenWorldMap((c and c.m) or current.mapID)
    end, L("Abre la zona en el mapa del mundo del juego con un marcador en el PNJ."))
    btnSave = MakeButton(L("Estoy junto a él"), 130, function()
        if not current.npc then return end
        local m, x, y = ns.PlayerPosition()
        if m then
            ns.SaveCoords(current.npc[3], m, x, y, true, true)
            ns.Print((L("Ubicación de %s guardada con tu posición actual.")):format(current.npc[3]))
            Map.ShowNPC(current.npc)
            ns.RequestRefresh()
        else
            ns.Print(L("No se pudo leer tu posición aquí."))
        end
    end, L("Guarda tu posición actual como ubicación de este PNJ (úsalo cuando estés a su lado)."))
    btnClear = MakeButton(L("Olvidar ubicación"), 130, function()
        if not current.npc then return end
        if ns.acct then ns.acct.coords[current.npc[3]] = nil end
        ns.char.coords[current.npc[3]] = nil
        Map.Render(); ns.RequestRefresh()
    end, L("Borra la ubicación que guardaste para este PNJ y vuelve a usar la de la web."))

    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed < 0.2 then return end
        elapsed = 0
        Map.UpdatePlayer()
    end)
    frame:Hide()
end

function Map.UpdatePlayer()
    if not current.mapID then playerDot:Hide(); return end
    local m, x, y = ns.PlayerPosition()
    if m ~= current.mapID then playerDot:Hide(); return end
    playerDot:ClearAllPoints()
    playerDot:SetPoint("CENTER", area, "TOPLEFT", x * MAP_W, -y * current.layerH)
    if GetPlayerFacing and playerDot.tex.SetRotation then
        local ok, f = pcall(GetPlayerFacing)
        if ok and type(f) == "number" then pcall(playerDot.tex.SetRotation, playerDot.tex, f) end
    end
    playerDot:Show()
end

local function DrawTiles(mapID)
    for _, t in ipairs(tiles) do t:Hide() end
    if not (mapID and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return false end
    local okL, layers = pcall(C_Map.GetMapArtLayers, mapID)
    local layer = okL and layers and layers[1]
    local okT, textures = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
    if not layer or not okT or type(textures) ~= "table" or #textures == 0 then return false end
    local scale = MAP_W / layer.layerWidth
    local h = layer.layerHeight * scale
    current.layerH = h
    area:SetHeight(h)
    local cols = math.ceil(layer.layerWidth / layer.tileWidth)
    local tw, th = layer.tileWidth * scale, layer.tileHeight * scale
    for i, tex in ipairs(textures) do
        local t = tiles[i]
        if not t then t = area:CreateTexture(nil, "ARTWORK"); tiles[i] = t end
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        t:ClearAllPoints()
        t:SetSize(tw, th)
        t:SetPoint("TOPLEFT", area, "TOPLEFT", col * tw, -row * th)
        t:SetTexture(tex)
        t:Show()
    end
    return true
end

function Map.Render()
    local mapID, npc = current.mapID, current.npc
    local ok = DrawTiles(mapID)
    if not ok then current.layerH = 420; area:SetHeight(420) end
    noMap:SetShown(not ok)

    -- Pines: todos los PNJ de las guías con coordenadas en este mapa
    local n = 0
    selGlow:Hide(); selLabel:Hide()
    if mapID then
        for name, e in pairs(ns.npcIndex) do
            local c = ns.GetCoords(name)
            local selected = npc and npc[3] == name
            if c and c.m == mapID and (selected or ns.NPCVisible(e.npc)) then
                n = n + 1
                local p = GetPin(n)
                p.npc = selected and npc or e.npc
                p:SetSize(selected and 24 or 12, selected and 24 or 12)
                p:SetFrameLevel(area:GetFrameLevel() + (selected and 7 or 5))
                p.tex:SetTexture(selected and "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
                    or "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. (e.npc[1] == "H" and "7" or e.npc[1] == "A" and "6" or "2"))
                p:ClearAllPoints()
                p:SetPoint("CENTER", area, "TOPLEFT", c.x * MAP_W, -c.y * current.layerH)
                p:Show()
                if selected then
                    selGlow:ClearAllPoints(); selGlow:SetPoint("CENTER", p, "CENTER"); selGlow:Show()
                    selLabel:SetText(name)
                    selLabel:ClearAllPoints()
                    if c.x > 0.75 then selLabel:SetPoint("RIGHT", p, "LEFT", -4, 0) else selLabel:SetPoint("LEFT", p, "RIGHT", 4, 0) end
                    selLabel:Show()
                end
            end
        end
    end
    for i = n + 1, #pins do pins[i]:Hide() end

    -- Textos y botones
    local zoneName = mapID and C_Map and C_Map.GetMapInfo and (C_Map.GetMapInfo(mapID) or {}).name or "?"
    if npc then
        title:SetText(W.FactionColor(npc[1]) .. (npc.label and L(npc.label) or npc[3]) .. "|r  " .. W.GREY .. "-  " .. ns.ZoneName(npc[2]) .. "|r")
        sub:SetText(L(npc[4]) or "")
    else
        title:SetText(zoneName or "")
        sub:SetText(L("PNJ de las guías en esta zona: cruz roja = Horda, cuadrado azul = Alianza, círculo naranja = neutral. Pasa el ratón por un icono para ver quién es."))
    end
    local c = npc and ns.GetCoords(npc[3])
    local inst = npc and ns.InstanceInfo(npc[3])
    local text
    if npc and c then
        local src = (c.builtin and (npc.label and L("(de la guía)") or L("(wow-professions.com)"))) or (c.manual and L("(fijada por ti)")) or (c.p and L("(exacta)")) or L("(aproximada: guardada al verlo de lejos)")
        text = (L("%sCoordenadas:|r %.1f, %.1f %s")):format(W.GREEN, c.x * 100, c.y * 100, src)
        if c.m ~= mapID then text = text .. W.ORANGE .. L("  Está en otro mapa.") .. "|r" end
        text = text .. "  " .. W.GREY .. L("Clic derecho en la estrella o «Poner marcador» para guiarte hasta él.") .. "|r"
    elseif inst then
        text = W.ORANGE .. (L("Está dentro de la mazmorra %s, así que no aparece en el mapa de la zona.")):format(ns.DungeonName(inst.dungeon)) .. "|r " .. L("Sigue la indicación de arriba.")
    elseif npc then
        text = W.ORANGE .. L("No hay coordenadas para este PNJ.|r ")
            .. L("Puedes hacer Ctrl+clic en el mapa para marcarla tú, o pulsar «Estoy junto a él». Mientras tanto, usa la indicación de arriba o pregunta a un guardia.")
    else
        text = L("Ctrl+clic: no hay PNJ seleccionado. Abre un PNJ desde la guía para poder marcar su ubicación.")
    end
    info:SetText(text)
    info:ClearAllPoints()
    info:SetPoint("TOPLEFT", area, "BOTTOMLEFT", 2, -8)
    info:SetWidth(MAP_W - 4)

    btnWaypoint:ClearAllPoints(); btnWorld:ClearAllPoints(); btnSave:ClearAllPoints(); btnClear:ClearAllPoints()
    btnWaypoint:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -8)
    btnWorld:SetPoint("LEFT", btnWaypoint, "RIGHT", 6, 0)
    btnSave:SetPoint("LEFT", btnWorld, "RIGHT", 6, 0)
    btnClear:SetPoint("LEFT", btnSave, "RIGHT", 6, 0)
    if c then btnWaypoint:Enable() else btnWaypoint:Disable() end
    if mapID then btnWorld:Enable() else btnWorld:Disable() end
    if npc then btnSave:Enable() else btnSave:Disable() end
    local saved = npc and ns.char and ((ns.acct and ns.acct.coords[npc[3]]) or ns.char.coords[npc[3]])
    if saved then btnClear:Enable() else btnClear:Disable() end
    frame:SetHeight(62 + current.layerH + 8 + info:GetStringHeight() + 48)
    Map.UpdatePlayer()
end

function Map.ShowNPC(npc)
    if not frame then Create() end
    local c = ns.GetCoords(npc[3])
    current.npc = npc
    local inst = ns.InstanceInfo(npc[3])
    current.mapID = (c and c.m) or ns.ResolveMapID((inst and inst.zone) or npc[2])
    frame:Show()
    Map.Render()
end

function Map.ShowZone(zoneKey)
    if not frame then Create() end
    current.npc = nil
    if zoneKey then
        current.mapID = ns.ResolveMapID(zoneKey)
    else
        current.mapID = select(1, ns.PlayerPosition())
    end
    frame:Show()
    Map.Render()
end

function Map.IsShown() return frame and frame:IsShown() end
