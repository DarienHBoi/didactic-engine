local _, ns = ...
local U = ns.UI
U.indicators={}
local seals={upgrade="Interface\\AddOns\\GearWise\\Assets\\SealUpgrade",unknown="Interface\\AddOns\\GearWise\\Assets\\SealUnknown",enhanced="Interface\\AddOns\\GearWise\\Assets\\SealEnchanted"}
-- The generated symbols have different transparent margins. Crop to equal,
-- centered visible silhouettes so every state lines up at the same slot anchor.
local sealBounds={upgrade={28,121,16.5,109.5},unknown={7,102,7,102},enhanced={13.5,105.5,14,106}}
local sealScale=.70
local sealSize=34*sealScale
local leftSlots={[1]=true,[2]=true,[3]=true,[15]=true,[5]=true,[9]=true}
local function cursorHasItem()
 return GetCursorInfo and GetCursorInfo()=="item" or CursorHasItem and CursorHasItem()
end
local function placeCursorItem(parent,id)
 if not cursorHasItem() then return false end
 -- Use the native slot's drop handler, including its equipment validation.
 local receive=parent:GetScript("OnReceiveDrag") or PaperDollItemSlotButton_OnReceiveDrag
 if receive then receive(parent) elseif PickupInventoryItem then PickupInventoryItem(id) end
 GameTooltip:Hide()
 -- Consume the interaction even if the game rejects this item for the slot.
 return true
end
local function chosenProfile()
 if U.profile then return U.profile end
 for _,p in ipairs(ns.Advice.Profiles()) do if p.id==ns.char.preferredProfile then return p end end
 return ns.Advice.Detect()
end
function U.AttachSlots()
    if not ns.enabled or not CharacterFrame or (InCombatLockdown and InCombatLockdown()) then return end
    for _, slot in ipairs(ns.slots) do
        local id=slot.id
        local parent=_G["Character"..slot.key]
        if parent and not U.indicators[id] then
            local b=CreateFrame("Button",nil,parent,"BackdropTemplate")
            b:SetSize(sealSize,sealSize)
            local corner=leftSlots[id] and "TOPLEFT" or "TOPRIGHT"
            local outside=sealSize*.66
            b:SetPoint(corner,parent,corner,leftSlots[id] and -outside or outside,11*sealScale)
            b:SetFrameLevel(parent:GetFrameLevel()+8)
            -- Opaque silhouette separates the bronze seal from the equipment border.
            local shadow=b:CreateTexture(nil,"BACKGROUND");shadow:SetPoint("CENTER")
            shadow:SetVertexColor(0,0,0,1);b.shadow=shadow
            local icon=b:CreateTexture(nil,"ARTWORK");icon:SetPoint("CENTER");b.icon=icon
            b.Paint=function(self)
                local emphasized=self.hovered or self.selected
                local size=(emphasized and 36 or 34)*sealScale
                self.icon:SetSize(size,size);self.icon:SetVertexColor(1,1,1,1)
                self.shadow:SetSize(size+4*sealScale,size+4*sealScale)
                if self.selection then self.selection:SetShown(emphasized and true or false) end
            end
            b:RegisterForClicks("LeftButtonUp")
            b:SetScript("OnClick",function()
                if not placeCursorItem(parent,id) then U.Open(id) end
            end)
            b:SetScript("OnReceiveDrag",function() placeCursorItem(parent,id) end)
            b:SetScript("OnEnter",function(self)
                self.hovered=true;self:Paint()
                if cursorHasItem() then GameTooltip:Hide();return end
                local inspection=ns.API.Inspect(id)
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText("GearWise · "..slot.label)
                local label=self.state=="upgrade" and ns.L("Passende Verbesserung verfügbar") or self.state=="enhanced" and ns.L("Verzauberung vorhanden") or ns.L("Möglichkeiten noch ungeklärt")
                GameTooltip:AddLine(label,1,.82,.45,true)
                GameTooltip:AddLine(inspection.status,.85,.82,.73,true)
                GameTooltip:AddLine(ns.L("Klicken: Möglichkeiten ansehen"),.46,.80,.64,true)
                if inspection.state=="enhanced" then GameTooltip:AddLine(ns.L("Verzaubert heißt nicht automatisch optimal."),.75,.75,.75,true) end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave",function(self) self.hovered=nil;self:Paint();GameTooltip:Hide() end)
            local selection=parent:CreateTexture(nil,"OVERLAY")
            selection:SetTexture("Interface\\Buttons\\UI-Quickslot2");selection:SetSize(64,64);selection:SetPoint("CENTER",parent,"CENTER")
            selection:SetVertexColor(1,.76,.32,.85);selection:Hide();b.selection=selection
            b:Paint();U.indicators[id]=b
            -- Observe native slot clicks without replacing Blizzard's equipment handlers.
            parent:HookScript("OnClick",function()
                if U.panel and U.panel:IsShown() then U.SelectSlot(id) end
            end)
        end
    end
    if not U.characterHooked then
        U.characterHooked=true
        CharacterFrame:HookScript("OnShow",function()
            U.RefreshIndicators()
            if U.panel:IsShown() and not ns.db.settings.detached then U.PlacePanel() end
        end)
        CharacterFrame:HookScript("OnHide",function()
            if not ns.db.settings.detached and U.tab~="cart" then U.panel:Hide() end
        end)
    end
end
function U.RefreshSelection()
    for id,b in pairs(U.indicators) do
        b.selected=U.panel and U.panel:IsShown() and U.tab~="cart" and U.slot==id
        b:Paint()
    end
end
function U.RefreshIndicators()
    U.RefreshSelection()
    if not CharacterFrame or not CharacterFrame:IsShown() then return end
    local profile=chosenProfile()
    for id,b in pairs(U.indicators) do
        local inspection=ns.API.Inspect(id)
        local state=inspection.state=="enhanced" and "enhanced" or "unknown"
        local candidates=ns.bySlot[id] or {}
        local known=inspection.enchantID==0 or inspection.current and next(ns.Advice.Stats(inspection.current).stats)~=nil
        local baseline=inspection.current and ns.Advice.Score(inspection.current,profile) or 0
        if known then
            for _,option in ipairs(candidates) do
                if ns.Rules.Evaluate(option,inspection.context)=="usable" and ns.Advice.Relevant(option,profile)
                    and ns.Advice.Score(option,profile)>baseline then state="upgrade";break end
            end
        end
        b.state=state;b.icon:SetTexture(seals[state]);b.shadow:SetTexture(seals[state])
        local bounds=sealBounds[state]
        b.icon:SetTexCoord(bounds[1]/128,bounds[2]/128,bounds[3]/128,bounds[4]/128)
        b.shadow:SetTexCoord(bounds[1]/128,bounds[2]/128,bounds[3]/128,bounds[4]/128)
        b:Paint()
        b:SetShown(ns.db.settings.showIndicators and inspection.context.item~=nil and inspection.state~="ignored"
            and (#candidates>0 or inspection.state=="enhanced")
            and (not ns.db.settings.onlyUpgradeIndicators or state=="upgrade"))
    end
end
function U.RefreshMinimap()
    if U.minimap then U.minimap:SetShown(ns.db.settings.showMinimap) end
end
function U.CreateMinimap()
    if not Minimap then return end
    local b=CreateFrame("Button","GearWiseForeverMinimap",Minimap)
    b:SetSize(30,30);b:SetFrameLevel(8)
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon=b:CreateTexture(nil,"ARTWORK");icon:SetSize(21,21);icon:SetPoint("CENTER")
    icon:SetTexture(ns.Theme.minimapLogoPath);icon:SetTexCoord(0,1,0,1);b.logo=icon
    local border=b:CreateTexture(nil,"OVERLAY");border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(52,52);border:SetPoint("TOPLEFT")
    local function radii()
        return Minimap:GetWidth()/2+5,Minimap:GetHeight()/2+5
    end
    local function position()
        local angle=math.rad(ns.db.settings.minimapAngle or 220)
        local rx,ry=radii()
        b:ClearAllPoints();b:SetPoint("CENTER",Minimap,"CENTER",math.cos(angle)*rx,math.sin(angle)*ry)
    end
    Minimap:HookScript("OnSizeChanged",position)
    b:SetScript("OnShow",position)
    b:RegisterForClicks("LeftButtonUp","RightButtonUp")
    b:SetScript("OnClick",function(_,button)
        if button=="RightButton" then
            U.ToggleCart()
        elseif button=="LeftButton" then U.OpenPlanner() end
    end)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart",function()
        b:SetScript("OnUpdate",function()
            local x,y=GetCursorPosition();local scale=Minimap:GetEffectiveScale();local cx,cy=Minimap:GetCenter()
            local rx,ry=radii()
            ns.db.settings.minimapAngle=math.deg(math.atan2((y/scale-cy)/ry,(x/scale-cx)/rx))
            position()
        end)
    end)
    b:SetScript("OnDragStop",function() b:SetScript("OnUpdate",nil) end)
    b:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_LEFT");GameTooltip:SetText("GearWise")
        GameTooltip:AddLine(ns.L("Linksklick: Planer & Rezepte öffnen"),.8,.8,.8)
        GameTooltip:AddLine(ns.L("Rechtsklick: Einkaufsliste öffnen / schließen"),.8,.8,.8)
        GameTooltip:AddLine(ns.L("Ziehen: Symbol verschieben"),.8,.8,.8);GameTooltip:Show()
    end)
    b:SetScript("OnLeave",function() GameTooltip:Hide() end)
    U.minimap=b;position();U.RefreshMinimap()
end


-- Each launcher belongs to its GearWise window and inherits visibility and scale.
function U.RefreshCartLauncher(entries)
    if not U.cartLaunchers then return end
    if not entries then local _;_,entries=ns.Shopping.GetCart() end
    local count=0;for _,entry in ipairs(entries or {}) do count=count+(entry.quantity or 1) end
    for _,b in ipairs(U.cartLaunchers) do
    b.count=count;b.active=U.cartWindow and U.cartWindow:IsShown() or false
    b.badge.text:SetText(count>99 and "99+" or tostring(count));ns.Theme.Font(b.badge.text,count>99 and 8 or 10)
    ns.Theme.PaintCartBadge(b);b.badge:SetShown(count>0);b:Show()
    end
end
function U.CreateCartLauncher(parent)
    if not parent or parent.cartLauncher then return end
    local T=ns.Theme
    local b=CreateFrame("Button",nil,parent)
    parent.cartLauncher=b;U.cartLaunchers=U.cartLaunchers or {};table.insert(U.cartLaunchers,b)
    b:SetSize(30,30);b:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",-18,7)
    b:SetFrameLevel(parent:GetFrameLevel()+8)
    b:RegisterForClicks("LeftButtonUp");T.CaptureWheel(b)
    local glyph=CreateFrame('Frame',nil,b);b.glyph=glyph
    glyph:SetSize(46,46);glyph:SetScale(.65);glyph:SetPoint('CENTER');glyph:EnableMouse(false);T.CartSymbol(glyph)
    b.badge=T.CartBadge(b);b.badge:SetFrameLevel(glyph:GetFrameLevel()+1)
    b:SetScript("OnClick",function() U.ToggleCart() end)
    b:SetScript("OnEnter",function(self)
        self.hovered=true;T.PaintCartBadge(self)
        GameTooltip:SetOwner(self,"ANCHOR_LEFT");GameTooltip:SetText(ns.L("GearWise · Einkaufsliste"))
        GameTooltip:AddLine(ns.L("Linksklick: Einkaufsliste öffnen / schließen"),.94,.89,.77,true)
        if self.count>0 then GameTooltip:AddLine(self.count..ns.L(" Verbesserungen"),1,.80,.38) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave",function(self) self.hovered=nil;T.PaintCartBadge(self);GameTooltip:Hide() end)
    b:SetScript("OnShow",function() U.RefreshCartLauncher() end)
    b:SetScript("OnHide",function(self) if self.hovered then GameTooltip:Hide() end;self.hovered=nil end)
    U.RefreshCartLauncher()
end
