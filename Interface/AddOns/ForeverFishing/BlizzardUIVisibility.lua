-- Forever Fishing
-- Copyright © 2026 Hamish336. All Rights Reserved.
-- Applies to original Forever Fishing code and assets only.
-- Blizzard-owned assets and trademarks remain property of Blizzard Entertainment.
-- Unauthorized redistribution or modification is prohibited.
local FF = _G.ForeverFishing

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

function FF:GetBlizzardUIHideMode()
    local mode=self.db and self.db.blizzardUIHideMode
    if mode=="never" or mode=="fishing" or mode=="casts" then return mode end
    return self.db and self.db.hideBlizzardUIWhileFishing==true and "fishing" or "never"
end
function FF:InitializeFishingViewSettings()
    self.db.blizzardUIHideMode=self:GetBlizzardUIHideMode()
    -- Compatibility for the older fallback settings surface. The mode owns policy.
    self.db.hideBlizzardUIWhileFishing=self.db.blizzardUIHideMode~="never"
end

function FF:ShouldHideFishingBlizzardUI()
    if not (self.bar and self.bar:IsShown()) then return false end
    local mode=self:GetBlizzardUIHideMode()
    if mode=="fishing" then return true end
    if mode~="casts" then return false end
    local phase=self.fishingViewPhase
    -- Keep native UI hidden through the short HUD return fade. A new channel
    -- can reverse that fade without briefly exposing the native interface.
    return phase and (phase.channel or GetTime()<phase.restoreAt) or self.minimalViewState~=nil
end

-- Prepare native tooltip parents before UIParent is hidden. Waiting for a
-- successful SetOwner is too late if the hidden parent prevents that setup.
local function Under(frame, ancestor)
    for _=1,64 do
        if frame==ancestor then return true end
        frame=frame and frame.GetParent and frame:GetParent()
        if not frame then return false end
    end
    return false
end
-- Borrow only the native minimap hierarchy, never Show a native frame or
-- change tracking. The transparent root is outside the Minimal HUD fade.
function FF:ReleaseFishingMinimap()
    local state=self.fishingMinimapState
    if not state or self.fishingMinimapChanging then return end
    if InCombat() then self.fishingMinimapRestorePending=true; return end
    self.fishingMinimapChanging=true
    local frame=state.frame
    if frame:GetParent()==state.root then
        local strata,level=frame:GetFrameStrata(),frame:GetFrameLevel()
        if frame:GetScale()==state.appliedScale then frame:SetScale(state.scale) end
        frame:SetParent(state.parent)
        frame:SetFrameStrata(strata==state.appliedStrata and state.strata or strata)
        frame:SetFrameLevel(level==state.appliedLevel and state.level or level)
    end
    state.root:Hide()
    self.fishingMinimapState,self.fishingMinimapRestorePending=nil,nil
    self.fishingMinimapChanging=nil
end
local function MinimapShown(frame)
    -- UIParent may already be addon-hidden when the preference is enabled.
    -- Every native child/intermediate parent must still be logically shown.
    for _=1,64 do
        if frame==UIParent then return not frame.GetAlpha or frame:GetAlpha()>0 end
        if not frame or not frame:IsShown() or (frame.GetAlpha and frame:GetAlpha()<=0) then return false end
        frame=frame:GetParent()
    end
    return false
end
function FF:SyncFishingMinimapVisibility(hiding)
    if self.fishingMinimapChanging then return end
    local active=self.db and self.db.showFishingMinimap==true and self:GetBlizzardUIHideMode()~="never"
        and self.bar and self.bar:IsShown() and not self.fishingUIManualOverride
        and UIParent and (hiding or (self.fishingUIHiddenByAddon and not UIParent:IsShown()))
    if not active or self.fishingMinimapRestorePending then
        self:ReleaseFishingMinimap()
        if not active or self.fishingMinimapState then return end
    end
    -- Existing records retain identity, hidden state and later external edits.
    if self.fishingMinimapState or InCombat() then return end
    local frame=MinimapCluster or Minimap
    if not (frame and Minimap and self.visibilityRoot and self.visibilityRoot:GetParent()~=UIParent)
        or not Under(Minimap,frame) or not Under(frame,UIParent) or not MinimapShown(Minimap) then return end
    local rootAlpha=self.visibilityRoot.GetEffectiveAlpha and self.visibilityRoot:GetEffectiveAlpha() or 1
    if rootAlpha<=0 then return end
    local root=self.fishingMinimapRoot or CreateFrame("Frame",nil,self.visibilityRoot,"SecureHandlerBaseTemplate")
    root:SetAllPoints(UIParent); root:EnableMouse(false)
    local state={frame=frame,root=root,parent=frame:GetParent(),scale=frame:GetScale(),
        strata=frame:GetFrameStrata(),level=frame:GetFrameLevel()}
    state.appliedScale=frame:GetEffectiveScale()/root:GetEffectiveScale()
    -- Preserve native parent opacity as well as the frame's own alpha.
    local parentAlpha=state.parent.GetEffectiveAlpha and state.parent:GetEffectiveAlpha() or 1
    root:SetAlpha(parentAlpha/rootAlpha); root:Show()
    self.fishingMinimapChanging=true
    self.fishingMinimapRoot,self.fishingMinimapState=root,state
    frame:SetParent(root); frame:SetScale(state.appliedScale)
    frame:SetFrameStrata(state.strata); frame:SetFrameLevel(state.level)
    state.appliedScale=frame:GetScale()
    state.appliedStrata,state.appliedLevel=frame:GetFrameStrata(),frame:GetFrameLevel()
    self.fishingMinimapChanging=nil
end
function FF:SetFishingMinimapShown(enabled)
    if not self.db then return end
    self.db.showFishingMinimap=enabled==true
    self:ReapplyFishingViewSettings()
    if self.settingsPanel and self.settingsPanel.RefreshFishingViewControls then self.settingsPanel:RefreshFishingViewControls() end
end
function FF:GetFishingMinimapTooltipOwner(owner)
    local state=self.fishingMinimapState
    if owner==UIParent and state and state.frame:GetParent()==state.root
        and Minimap and Under(Minimap,state.frame) and Minimap:IsVisible()
        and Minimap.IsMouseOver and Minimap:IsMouseOver() then return Minimap end
    return owner
end
local function TooltipFrames()
    local frames,seen={},{}
    local function Add(frame)
        if frame and not seen[frame] then seen[frame]=true; frames[#frames+1]=frame end
    end
    Add(GameTooltip)
    for _,frame in ipairs(GameTooltip and GameTooltip.shoppingTooltips or {}) do Add(frame) end
    for index=1,3 do Add(_G["ShoppingTooltip"..index]) end
    return frames
end
local function CanMoveTooltip(frame)
    return not (InCombat() and frame.IsProtected and frame:IsProtected())
end
function FF:ReleaseFishingTooltipParents(hideComparisons)
    local state=self.fishingUITooltipState
    if not state or self.fishingUITooltipChanging then return end
    self.fishingUITooltipChanging=true
    for frame,record in pairs(state.frames) do
        if CanMoveTooltip(frame) then
            if hideComparisons and frame~=state.tip then frame:Hide() end
            -- A later parent/scale change by another owner wins.
            if frame:GetParent()==record.appliedParent then
                local strata=frame:GetFrameStrata()
                local level=frame:GetFrameLevel()
                if strata==record.appliedStrata then strata=record.strata end
                if level==record.appliedLevel then level=record.level end
                if frame:GetScale()==record.appliedScale then frame:SetScale(record.scale) end
                frame:SetParent(record.parent)
                -- SetParent can inherit the new parent's drawing order.
                frame:SetFrameStrata(strata)
                frame:SetFrameLevel(level)
            end
            state.frames[frame]=nil
        end
    end
    self.fishingUITooltipChanging=nil
    if not next(state.frames) then self.fishingUITooltipState=nil end
end
function FF:InstallFishingTooltipHooks()
    if not (GameTooltip and hooksecurefunc) then return end
    self.fishingUITooltipHooks=self.fishingUITooltipHooks or {}
    for _,tip in ipairs(TooltipFrames()) do
        if not self.fishingUITooltipHooks[tip] then
            self.fishingUITooltipHooks[tip]=true
            -- Include comparison frames created after the initial preparation.
            hooksecurefunc(tip,"SetOwner",function(frame,owner,anchor,...)
                -- Native marker hover uses hidden UIParent as owner. Substitute
                -- the visible map before native content is filled, preserving
                -- its exact cursor anchor/offsets; never reset content on Show.
                if frame==GameTooltip and not self.fishingUIMinimapTooltipChanging and CanMoveTooltip(frame) then
                    local visible=self:GetFishingMinimapTooltipOwner(owner)
                    if visible~=owner then
                        self.fishingUIMinimapTooltipChanging=true
                        frame:SetOwner(visible,anchor,...)
                        self.fishingUIMinimapTooltipChanging=nil
                    end
                end
                self:SyncFishingTooltipVisibility()
            end)
            hooksecurefunc(tip,"Show",function() self:SyncFishingTooltipVisibility() end)
            tip:HookScript("OnShow",function() self:SyncFishingTooltipVisibility() end)
            if tip==GameTooltip then
                tip:HookScript("OnHide",function()
                    -- Keep the group ready for the next hover while UI is hidden.
                    if self.fishingUITooltipChanging then return end
                    for _,compare in ipairs(TooltipFrames()) do
                        if compare~=GameTooltip and CanMoveTooltip(compare) then compare:Hide() end
                    end
                end)
            end
        end
    end
    if type(GameTooltip_ShowCompareItem)=="function"
        and self.fishingUITooltipCompareHook~=GameTooltip_ShowCompareItem then
        hooksecurefunc("GameTooltip_ShowCompareItem",function() self:SyncFishingTooltipVisibility() end)
        self.fishingUITooltipCompareHook=GameTooltip_ShowCompareItem
    end
end
function FF:SyncFishingTooltipVisibility(hiding)
    if self.fishingUITooltipChanging then return end
    local tip,root=GameTooltip,self.visibilityRoot
    local owner=tip and tip.GetOwner and tip:GetOwner()
    -- Native Minimap_OnUpdate anchors marker tooltips to UIParent. Permit
    -- this owner only over the still-owned, visible native minimap.
    owner=self:GetFishingMinimapTooltipOwner(owner)
    local state=self.fishingUITooltipState
    local active=self:GetBlizzardUIHideMode()~="never" and self.bar and self.bar:IsShown()
        and UIParent and (hiding or not UIParent:IsShown())
        and root and root:GetParent()~=UIParent
    if state and (not active or state.tip~=tip) then
        self:ReleaseFishingTooltipParents(state.tip~=tip)
        state=self.fishingUITooltipState
    end
    if not active then return end
    self:InstallFishingTooltipHooks()
    local allowed=owner and owner:IsVisible() and Under(owner,root)
    -- Borrowing the parent must not reveal Blizzard/other-addon tooltips.
    if not allowed then
        for _,frame in ipairs(TooltipFrames()) do
            if frame:IsShown() and CanMoveTooltip(frame) then frame:Hide() end
        end
    end
    if allowed then
        self.fishingUITooltipOwnerHooks=self.fishingUITooltipOwnerHooks or setmetatable({},{__mode="k"})
        if not self.fishingUITooltipOwnerHooks[owner] then
            self.fishingUITooltipOwnerHooks[owner]=true
            owner:HookScript("OnHide",function(hidden)
                local current=GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()
                local state=self.fishingUITooltipState
                if (current==hidden or (current==UIParent and hidden==Minimap and state and state.owner==hidden))
                    and CanMoveTooltip(GameTooltip) then GameTooltip:Hide() end
            end)
        end
    end
    if not state then state={tip=tip,frames={}}; self.fishingUITooltipState=state end
    state.owner=allowed and owner or nil
    self.fishingUITooltipChanging=true
    for _,frame in ipairs(TooltipFrames()) do
        if not state.frames[frame] and Under(frame,UIParent) and CanMoveTooltip(frame) then
            local parent,scale=frame:GetParent(),frame:GetScale()
            local effective,rootScale=frame:GetEffectiveScale(),root:GetEffectiveScale()
            local applied=effective/rootScale
            state.frames[frame]={parent=parent,scale=scale,strata=frame:GetFrameStrata(),level=frame:GetFrameLevel(),
                appliedParent=root,appliedScale=applied}
            frame:SetParent(root)
            frame:SetScale(applied)
        end
        local record=state.frames[frame]
        if record and frame:GetParent()==record.appliedParent and CanMoveTooltip(frame) then
            -- Native owner setup and reparenting can inherit a window's layer.
            -- The whole group must draw above that window, including Journal.
            local level=math.max(record.level,root:GetFrameLevel()+10,allowed and owner:GetFrameLevel()+10 or 0)
            record.appliedStrata,record.appliedLevel="TOOLTIP",level
            if frame:GetFrameStrata()~="TOOLTIP" then frame:SetFrameStrata("TOOLTIP") end
            if frame:GetFrameLevel()~=level then frame:SetFrameLevel(level) end
        end
    end
    self.fishingUITooltipChanging=nil
end

local function BagOpen()
    local combined = _G.ContainerFrameCombinedBags
    if combined and combined.IsShown and combined:IsShown() then return true end
    for index = 1, NUM_CONTAINER_FRAMES or 13 do
        local frame = _G["ContainerFrame" .. index]
        if frame and frame.IsShown and frame:IsShown() then return true end
    end
    return false
end

local function TemporaryPanelOpen()
    return (WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()) or BagOpen()
end

local function CommandPanelOpen(name)
    if name=="ToggleWorldMap" or name=="OpenWorldMap" then
        return WorldMapFrame and WorldMapFrame:IsShown()
    end
    return BagOpen()
end

-- Native Camelot bindings, not assumed B/M keys. Observe before the native
-- binding runs; never replace it or invoke a second toggle from this handler.
local PANEL_BINDINGS={TOGGLEWORLDMAP={"ToggleWorldMap"},TOGGLEBACKPACK={"ToggleBackpack"},
    OPENALLBAGS={"ToggleAllBags"},TOGGLEBAG1={"ToggleBag",4},TOGGLEBAG2={"ToggleBag",3},
    TOGGLEBAG3={"ToggleBag",2},TOGGLEBAG4={"ToggleBag",1},TOGGLEREAGENTBAG1={"ToggleBag",5}}
function FF:SyncFishingTemporaryPanelInput()
    local active=self.fishingUIHiddenByAddon and self:GetBlizzardUIHideMode()~="never"
        and self.bar and self.bar:IsShown() and UIParent and not UIParent:IsShown()
        and not self.fishingUIManualOverride
    local watch=self.fishingUIPanelKeyWatcher
    if active and not watch and not InCombat() and GetBindingAction and self.visibilityRoot then
        watch=CreateFrame("Frame",nil,self.visibilityRoot)
        watch:EnableMouse(false)
        watch:EnableKeyboard(true)
        watch:SetPropagateKeyboardInput(true)
        watch:SetScript("OnKeyDown",function(_,key)
            if not (self.fishingUIHiddenByAddon and self:GetBlizzardUIHideMode()~="never"
                and self.bar and self.bar:IsShown()) or UIParent:IsShown() then return end
            if self.journalInputFocus or self.settingsKeyboardFocus or (self.capture and self.capture:IsShown())
                or (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()) then return end
            if IsShiftKeyDown and IsShiftKeyDown() then key="SHIFT-"..key end
            if IsControlKeyDown and IsControlKeyDown() then key="CTRL-"..key end
            if IsAltKeyDown and IsAltKeyDown() then key="ALT-"..key end
            -- Include overrides: a fishing action or another addon wins.
            local action=GetBindingAction(key,true)
            if self.RevealFishingChatForBinding and self:RevealFishingChatForBinding(action) then return end
            local command=PANEL_BINDINGS[action]
            if command and not self:RevealFishingUIForTemporaryPanel() and self.fishingUIRevealPending then
                self.fishingUIPanelRetryPending={name=command[1],args={command[2]},key=key,action=action}
            end
        end)
        self.bar:HookScript("OnHide",function() watch:Hide() end)
        self.fishingUIPanelKeyWatcher=watch
    end
    if watch then watch:SetShown(active and true or false) end
end

function FF:ScheduleFishingTemporaryPanelSync()
    if self.fishingUITemporarySyncQueued then return end
    self.fishingUITemporarySyncQueued = true
    local function Sync()
        self.fishingUITemporarySyncQueued = nil
        if TemporaryPanelOpen() then return end
        self.fishingUITemporaryReveal = nil
        self:SyncFishingUIVisibility()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, Sync) else Sync() end
end

function FF:RevealFishingUIForTemporaryPanel()
    if not (self:GetBlizzardUIHideMode()~="never" and self.bar and self.bar:IsShown())
        or self.fishingUIManualOverride or not (UIParent and UIParent.IsShown and UIParent.Show) then return false end
    if self.fishingUITemporaryReveal and UIParent:IsShown() then return true end
    if not self.fishingUIHiddenByAddon or UIParent:IsShown() then return false end
    if InCombat() then self.fishingUIRevealPending = true; return false end
    self.fishingUIChangeInProgress = true
    pcall(UIParent.Show, UIParent)
    self.fishingUIChangeInProgress = nil
    if not UIParent:IsShown() then self.fishingUIRevealPending = true; return false end
    self.fishingUIHiddenByAddon = nil
    self.fishingUITemporaryReveal = true
    self.fishingUIRevealPending = nil
    return true
end

function FF:InstallFishingTemporaryPanelHooks()
    if WorldMapFrame and WorldMapFrame.HookScript and not self.fishingUIMapVisibilityHooked then
        self.fishingUIMapVisibilityHooked = true
        WorldMapFrame:HookScript("OnShow", function()
            if self.fishingUIHiddenByAddon then self:RevealFishingUIForTemporaryPanel() end
        end)
        WorldMapFrame:HookScript("OnHide", function() self:ScheduleFishingTemporaryPanelSync() end)
    end
    self.fishingUIPanelFrameHooks = self.fishingUIPanelFrameHooks or {}
    local function HookFrame(frame)
        if not (frame and frame.HookScript) or self.fishingUIPanelFrameHooks[frame] then return end
        self.fishingUIPanelFrameHooks[frame] = true
        frame:HookScript("OnShow", function()
            if self.fishingUIChangeInProgress then return end
            if self.fishingUIHiddenByAddon then self:RevealFishingUIForTemporaryPanel() end
            self:ScheduleFishingTemporaryPanelSync()
        end)
        frame:HookScript("OnHide", function() self:ScheduleFishingTemporaryPanelSync() end)
    end
    HookFrame(_G.ContainerFrameCombinedBags)
    for index = 1, NUM_CONTAINER_FRAMES or 13 do HookFrame(_G["ContainerFrame" .. index]) end
    if not hooksecurefunc then return end
    self.fishingUIPanelCommandHooks = self.fishingUIPanelCommandHooks or {}
    for _, name in ipairs({ "ToggleBackpack", "ToggleBag", "OpenBackpack", "OpenBag",
        "OpenAllBags", "ToggleAllBags", "CloseBackpack", "CloseBag", "CloseAllBags",
        "ToggleWorldMap", "OpenWorldMap" }) do
        if not self.fishingUIPanelCommandHooks[name] and type(_G[name]) == "function" then
            local hookedName = name
            local ok = pcall(hooksecurefunc, name, function(...)
                if self.fishingUIPanelRetrying then return end
                self:InstallFishingTemporaryPanelHooks()
                if self.fishingUIHiddenByAddon and hookedName ~= "CloseBackpack"
                    and hookedName ~= "CloseBag" and hookedName ~= "CloseAllBags" then
                    local args = { ... }
                    if self:RevealFishingUIForTemporaryPanel() then
                        if not CommandPanelOpen(hookedName) then
                            self.fishingUIPanelRetrying = true
                            pcall(_G[hookedName], unpack(args))
                            self.fishingUIPanelRetrying = nil
                            self:InstallFishingTemporaryPanelHooks()
                        end
                    elseif self.fishingUIRevealPending then
                        self.fishingUIPanelRetryPending = { name = hookedName, args = args }
                    end
                end
                self:ScheduleFishingTemporaryPanelSync()
            end)
            if ok then self.fishingUIPanelCommandHooks[name] = true end
        end
    end
end

function FF:InstallFishingUIVisibilityHook()
    self:InstallFishingTooltipHooks()
    if self.fishingUIVisibilityHooked or not (UIParent and UIParent.HookScript) then return end
    local ok = pcall(UIParent.HookScript, UIParent, "OnShow", function()
        if FF.fishingUIChangeInProgress or not (FF:GetBlizzardUIHideMode()~="never")
            or not (FF.bar and FF.bar:IsShown()) then return end
        -- Manual show pauses clean view until the next cast, matching hide or setting edit.
        FF.fishingUIHiddenByAddon = nil
        FF.fishingUITemporaryReveal = nil
        FF.fishingUIRevealPending = nil
        FF.fishingUIPanelRetryPending = nil
        FF.fishingUIManualOverride = true
    end)
    self.fishingUIVisibilityHooked = ok
    if ok then
        UIParent:HookScript("OnShow",function()
            FF:SyncFishingMinimapVisibility()
            FF:SyncFishingTooltipVisibility()
            FF:SyncFishingTemporaryPanelInput()
            if FF.SyncFishingViewVisibility then FF:SyncFishingViewVisibility() end
        end)
        UIParent:HookScript("OnHide", function()
            if not FF.fishingUIChangeInProgress then
                -- Alt+Z show/hide is a pause/resume within this fishing session.
                -- Do not claim UI that was already hidden before fishing opened.
                if (FF.fishingUIManualOverride or FF.fishingUITemporaryReveal)
                    and FF:ShouldHideFishingBlizzardUI()
                    and FF.bar and FF.bar:IsShown() then
                    FF.fishingUIManualOverride = nil
                    FF.fishingUIHiddenByAddon = true
                end
                FF.fishingUITemporaryReveal = nil
                FF.fishingUIRevealPending = nil
                FF.fishingUIPanelRetryPending = nil
            end
            FF:SyncFishingMinimapVisibility(FF.fishingUIChangeInProgress)
            FF:SyncFishingTooltipVisibility()
            FF:SyncFishingTemporaryPanelInput()
            if FF.SyncFishingViewVisibility then FF:SyncFishingViewVisibility(FF.fishingUIChangeInProgress) end
        end)
    end
    self:InstallFishingTemporaryPanelHooks()
end

local function SyncFishingUIVisibility(self)
    self:SyncFishingMinimapVisibility()
    if self.SyncFishingViewVisibility then self:SyncFishingViewVisibility() end
    if self.fishingUIDeferredRestore then return end
    if not self:ShouldHideFishingBlizzardUI() then
        self.fishingUIHidePending=nil
        if self.fishingUIHiddenByAddon or self.fishingUIRestorePending then self:ReleaseFishingUIVisibility(false)
        else self:SyncFishingTooltipVisibility(); self:SyncFishingTemporaryPanelInput() end
        return
    end
    self:SyncFishingTooltipVisibility()
    self:SyncFishingTemporaryPanelInput()
    if not self.fishingUIVisibilityHooked or self.fishingUIRestorePending
        or not (self:GetBlizzardUIHideMode()~="never")
        or not (self.bar and self.bar:IsShown()) or self.fishingUIManualOverride
        or self.fishingUIHiddenByAddon or self.fishingUITemporaryReveal or TemporaryPanelOpen()
        or not (UIParent and UIParent.IsShown and UIParent.Hide)
        or not UIParent:IsShown() then return end
    -- Never hide the ancestor that contains Forever Fishing's own controls.
    if not (self.visibilityRoot and self.visibilityRoot.GetParent)
        or self.visibilityRoot:GetParent() == UIParent then return end
    if InCombat() then self.fishingUIHidePending = true; return end
    self.fishingUIHidePending = nil
    self.fishingUIChangeInProgress = true
    self:SyncFishingMinimapVisibility(true)
    self:SyncFishingTooltipVisibility(true)
    if self.SyncFishingViewVisibility then self:SyncFishingViewVisibility(true) end
    local ok = pcall(UIParent.Hide, UIParent)
    self:SyncFishingTooltipVisibility()
    self.fishingUIChangeInProgress = nil
    if not UIParent:IsShown() then
        self.fishingUIHiddenByAddon = true
    elseif ok then
        -- A different UI controller immediately showed it again.
        self.fishingUIManualOverride = true
    end
    self:SyncFishingTemporaryPanelInput()
    if self.SyncFishingViewVisibility then self:SyncFishingViewVisibility() end
end

function FF:SyncFishingUIVisibility()
    if self.fishingUISyncing or self.fishingUIChangeInProgress then return end
    self.fishingUISyncing=true
    SyncFishingUIVisibility(self)
    self.fishingUISyncing=nil
end

function FF:ReleaseFishingUIVisibility(endSession)
    self.fishingUIHidePending = nil
    self.fishingUITemporaryReveal = nil
    self.fishingUIRevealPending = nil
    self.fishingUIPanelRetryPending = nil
    if endSession then
        self.fishingUIDeferredRestore=nil
        self.fishingViewPhase=nil
        self.fishingUISettingsRestoreSerial = (self.fishingUISettingsRestoreSerial or 0) + 1
    end
    local restore = self.fishingUIHiddenByAddon or self.fishingUIRestorePending
    self.fishingUIHiddenByAddon = nil
    self:SyncFishingMinimapVisibility()
    if self.SyncFishingViewVisibility then self:SyncFishingViewVisibility() end
    self:SyncFishingTemporaryPanelInput()
    if endSession then self.fishingUIManualOverride = nil end
    if not restore then self:SyncFishingTooltipVisibility(); return end
    if not (UIParent and UIParent.IsShown and UIParent.Show) then return end
    if UIParent:IsShown() then self.fishingUIRestorePending = nil; self:SyncFishingTooltipVisibility(); return end
    if InCombat() then self.fishingUIRestorePending = true; return end
    -- Return tooltip parents only after showing UIParent; an intermediate
    -- parent hide would clear a live native comparison during the toggle.
    self.fishingUIChangeInProgress = true
    pcall(UIParent.Show, UIParent)
    self.fishingUIChangeInProgress = nil
    self.fishingUIRestorePending = not UIParent:IsShown() or nil
    self:SyncFishingTooltipVisibility()
end

-- Only our two reset confirmations borrow a shared native popup. Keep their
-- native buttons/Escape behavior; return the frame before another popup uses it.
function FF:ReleaseFishingResetPopup(dialog)
    local states=self.fishingUIResetPopups
    local record=states and states[dialog]
    if not record or (InCombat() and dialog.IsProtected and dialog:IsProtected()) then return end
    states[dialog]=nil
    if not next(states) then self.fishingUIResetPopups=nil end
    if dialog:GetParent()~=record.appliedParent then return end
    local scale,strata,level=dialog:GetScale(),dialog:GetFrameStrata(),dialog:GetFrameLevel()
    if scale==record.appliedScale then scale=record.scale end
    if strata==record.appliedStrata then strata=record.strata end
    if level==record.appliedLevel then level=record.level end
    dialog:SetParent(record.parent)
    dialog:SetScale(scale)
    dialog:SetFrameStrata(strata)
    dialog:SetFrameLevel(level)
end

function FF:ShowFishingResetPopup(key)
    local dialog=StaticPopup_Show(key)
    if not dialog or dialog:GetParent()~=UIParent then return dialog end
    local root=self:EnsureFishingVisibilityRoot()
    if root:GetParent()==UIParent then return dialog end
    local record={parent=dialog:GetParent(),scale=dialog:GetScale(),strata=dialog:GetFrameStrata(),
        level=dialog:GetFrameLevel(),appliedParent=root,
        appliedScale=dialog:GetEffectiveScale()/root:GetEffectiveScale(),appliedStrata="FULLSCREEN_DIALOG",
        appliedLevel=math.max(dialog:GetFrameLevel(),root:GetFrameLevel()+10)}
    self.fishingUIResetPopups=self.fishingUIResetPopups or {}
    self.fishingUIResetPopups[dialog]=record
    dialog:SetParent(root)
    dialog:SetScale(record.appliedScale)
    dialog:SetFrameStrata(record.appliedStrata)
    dialog:SetFrameLevel(record.appliedLevel)
    return dialog
end

function FF:ResumeFishingUIVisibility()
    for dialog in pairs(self.fishingUIResetPopups or {}) do
        if not dialog:IsShown() then self:ReleaseFishingResetPopup(dialog) end
    end
    if self.fishingUIRestorePending then self:ReleaseFishingUIVisibility(false) end
    local retry = self.fishingUIPanelRetryPending
    if retry and retry.key and GetBindingAction(retry.key,true)~=retry.action then
        retry=nil
        self.fishingUIPanelRetryPending=nil
    end
    if self.fishingUIRevealPending and (retry or TemporaryPanelOpen()) then
        if self:RevealFishingUIForTemporaryPanel() and retry and not CommandPanelOpen(retry.name) then
            self.fishingUIPanelRetrying = true
            pcall(_G[retry.name], unpack(retry.args))
            self.fishingUIPanelRetrying = nil
            self:InstallFishingTemporaryPanelHooks()
        end
    end
    self.fishingUIRevealPending = nil
    self.fishingUIPanelRetryPending = nil
    if self.fishingUIHidePending or (self:GetBlizzardUIHideMode()~="never") then
        self:SyncFishingUIVisibility()
    end
    self:ScheduleFishingTemporaryPanelSync()
    self:SyncFishingMinimapVisibility()
    self:SyncFishingTooltipVisibility()
end

-- Only an accepted new channel ends a manual reveal. The normal channel
-- refresh then applies current policy, temporary-panel and combat safeguards.
function FF:ResumeFishingUIHidingOnCast(resumed)
    if self.fishingUIManualOverride and not resumed and self.bar and self.bar:IsShown()
        and self:GetBlizzardUIHideMode()~="never" then
        self.fishingUIManualOverride = nil
        self:SyncFishingUIVisibility()
    end
end

-- Deliberate edits reconcile parent ownership and both subordinate views.
-- Routine sync never clears a player's temporary manual-show override.
function FF:ReapplyFishingViewSettings()
    if not self.db then return end
    if self:GetBlizzardUIHideMode()~="never" then
        if UIParent and UIParent:IsShown() then self.fishingUIHiddenByAddon = nil end
        self.fishingUIManualOverride = nil
        self.fishingUIRevealPending = nil
        self.fishingUIPanelRetryPending = nil
        if not TemporaryPanelOpen() then self.fishingUITemporaryReveal = nil end
        if self.fishingUIRestorePending and not InCombat() then self:ReleaseFishingUIVisibility(false) end
        self:SyncFishingUIVisibility()
    else self:SyncFishingUIVisibility() end
end

function FF:SetBlizzardUIHideMode(mode)
    if not self.db then return end
    if mode~="never" and mode~="fishing" and mode~="casts" then return end
    self.fishingUISettingsRestoreSerial = (self.fishingUISettingsRestoreSerial or 0) + 1
    self.fishingUIDeferredRestore=nil
    local serial = self.fishingUISettingsRestoreSerial
    local settings = self.settingsPanel
    local keepSettingsOpen = settings and settings:IsShown()
    self.db.blizzardUIHideMode=mode
    self.db.hideBlizzardUIWhileFishing=mode~="never"
    if self.UpdateFishingViewPhase then self:UpdateFishingViewPhase() end
    local deferRestore = not self:ShouldHideFishingBlizzardUI() and keepSettingsOpen and self.fishingUIHiddenByAddon
        and C_Timer and C_Timer.After
    self:SyncFishingTemporaryPanelInput()
    if deferRestore then
        self.fishingUIDeferredRestore=serial
        -- Let the toggle click finish before bringing UIParent back. Reassert
        -- the Settings window afterward if Blizzard's show path displaced it.
        C_Timer.After(0, function()
            if self.fishingUISettingsRestoreSerial ~= serial or not self.db then return end
            self.fishingUIDeferredRestore=nil
            if self:ShouldHideFishingBlizzardUI() then self:SyncFishingUIVisibility(); return end
            local reopen = self.settingsPanel == settings and settings:IsShown()
            self:ReleaseFishingUIVisibility(false)
            if reopen and self.settingsPanel == settings and self.ShowFloatingWindow then
                self:ShowFloatingWindow(settings)
                -- Restored Blizzard panels can change the shared fishing layer.
                -- Keep the window being edited visible for this transition.
                settings:SetFrameStrata("DIALOG")
            end
        end)
    else self:ReapplyFishingViewSettings() end
    if self.settingsPanel and self.settingsPanel.hideBlizzardUIWhileFishingButton then
        self.settingsPanel.hideBlizzardUIWhileFishingButton:SetState(self.db.hideBlizzardUIWhileFishing)
    end
    if self.settingsPanel and self.settingsPanel.generalHideBlizzardUIWhileFishingButton then
        self.settingsPanel.generalHideBlizzardUIWhileFishingButton:SetState(self.db.hideBlizzardUIWhileFishing)
    end
    if self.SyncFishingViewVisibility then self:SyncFishingViewVisibility() end
    if self.settingsPanel and self.settingsPanel.RefreshFishingViewControls then self.settingsPanel:RefreshFishingViewControls() end
    if self.RefreshCatchRecapSetting then self:RefreshCatchRecapSetting() end
end

function FF:SetHideBlizzardUIWhileFishing(enabled)
    self:SetBlizzardUIHideMode(enabled==true and "fishing" or "never")
end
