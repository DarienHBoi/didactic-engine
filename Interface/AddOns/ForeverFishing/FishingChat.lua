-- Forever Fishing
-- Copyright Ãƒâ€šÃ‚Â© 2026 Hamish336. All Rights Reserved.
-- Applies to original Forever Fishing code and assets only.
-- Blizzard-owned assets and trademarks remain property of Blizzard Entertainment.
-- Unauthorized redistribution or modification is prohibited.
local FF=_G.ForeverFishing
local MODES={hidden=true,always=true,whispers=true,guild=true}
local CHAT_BINDINGS={OPENCHAT=true,OPENCHATSLASH=true,REPLY=true,REPLY2=true}
local WHISPERS={"CHAT_MSG_WHISPER","CHAT_MSG_WHISPER_INFORM","CHAT_MSG_BN_WHISPER","CHAT_MSG_BN_WHISPER_INFORM"}
local function Combat() return InCombatLockdown and InCombatLockdown() end
local function Under(frame,ancestor)
    for _=1,64 do
        if frame==ancestor then return true end
        frame=frame and frame.GetParent and frame:GetParent()
        if not frame then return false end
    end
    return false
end
function FF:GetFishingChatMode()
    local mode=self.db and self.db.fishingChatMode
    return MODES[mode] and mode or "hidden"
end
function FF:SetFishingChatMode(mode)
    if not self.db or not MODES[mode] then return end
    self.db.fishingChatMode=mode
    -- Reconcile the shared parent/ownership state as well as this child view.
    self:ReapplyFishingViewSettings()
    if self.settingsPanel then self.settingsPanel:RefreshFishingViewControls() end
end
local function Roots()
    local list,seen={},{}
    local function Add(frame)
        if frame and not seen[frame] then seen[frame]=true; list[#list+1]=frame end
    end
    Add(GeneralDockManager)
    for _,name in ipairs(CHAT_FRAMES or {}) do Add(_G[name]) end
    for i=1,NUM_CHAT_WINDOWS or 10 do Add(_G["ChatFrame"..i]) end
    for _,name in ipairs(CHAT_FRAMES or {}) do
        Add(_G[name.."Tab"]); Add(_G[name.."EditBox"]); Add(_G[name.."Minimized"])
    end
    for i=1,NUM_CHAT_WINDOWS or 10 do
        local name="ChatFrame"..i
        Add(_G[name.."Tab"]); Add(_G[name.."EditBox"]); Add(_G[name.."Minimized"])
    end
    Add(ChatMenu); Add(TextToSpeechButtonFrame); Add(QuickJoinToastButton)
    -- Native chat item links still use the original item-reference group.
    Add(ItemRefTooltip); Add(ItemRefShoppingTooltip1); Add(ItemRefShoppingTooltip2)
    return list
end
local function Interacting(state)
    local over=false
    for _,frame in ipairs(state.members) do
        if frame:IsVisible() then
            if frame.HasFocus and frame:HasFocus() then return true end
            if frame.IsMouseOver and frame:IsMouseOver() then over=true end
        end
    end
    local held=IsMouseButtonDown and IsMouseButtonDown()
    state.dragging=held and (over or state.dragging) or nil
    local manager=Menu and Menu.GetManager and Menu.GetManager()
    local menu=manager and manager:GetOpenMenu()
    local owner=menu and menu:GetOwnerRegion()
    -- Native modern menus already use WorldFrame; keep chat present while its
    -- own menu/submenus are open without borrowing unrelated menu frames.
    return over or state.dragging or MOVING_CHATFRAME~=nil or (owner and Under(owner,state.root))
end
function FF:PaintFishingChat(elapsed)
    local state=self.fishingChatState
    if not state then return end
    local now=GetTime()
    local interaction=Interacting(state)
    if interaction or state.interacting then state.untilTime=now+12 end
    state.interacting=interaction
    -- Protected chat hierarchies cannot be hidden by an ordinary timer in
    -- combat. Keep them visible and start a fresh delay when combat ends.
    local visible=state.mode=="always" or interaction or now<(state.untilTime or 0) or Combat()
    local alpha=state.root:GetAlpha()
    local target=visible and 1 or 0
    alpha=target==1 and math.min(1,alpha+(elapsed or 0)*6) or math.max(0,alpha-(elapsed or 0)*4)
    state.root:SetAlpha(alpha)
    if alpha==0 and not Combat() then
        state.root:Hide(); state.root:SetScript("OnUpdate",nil)
    end
end
function FF:RevealFishingChatForBinding(action)
    if not CHAT_BINDINGS[action] or self:GetFishingChatMode()=="hidden" then return false end
    self:RevealFishingChat()
    return true
end
function FF:RevealFishingChat()
    local state=self.fishingChatState
    if not state or state.releasing then return end
    state.untilTime=GetTime()+12
    if not Combat() or not state.root:IsProtected() then state.root:Show() end
    state.root:SetAlpha(1)
    if state.mode~="always" then
        state.root:SetScript("OnUpdate",function(_,elapsed) self:PaintFishingChat(elapsed) end)
    end
end
function FF:ReleaseFishingChat()
    local state=self.fishingChatState
    if not state or self.fishingChatReleasing then return end
    self.fishingChatReleasing=true
    state.releasing=true
    state.root:SetScript("OnUpdate",nil)
    state.events:UnregisterAllEvents()
    state.root:SetAlpha(1)
    if Combat() then
        -- Leave visible controls usable until their native parents can return.
        self.fishingChatRestorePending=true
        state.events:RegisterEvent("PLAYER_REGEN_ENABLED")
        self.fishingChatReleasing=nil
        return
    end
    for frame,record in pairs(state.frames) do
        if frame:GetParent()==state.root then
            local strata,level=frame:GetFrameStrata(),frame:GetFrameLevel()
            if frame:GetScale()==record.appliedScale then frame:SetScale(record.scale) end
            frame:SetParent(record.parent)
            frame:SetFrameStrata(strata==record.appliedStrata and record.strata or strata)
            frame:SetFrameLevel(level==record.appliedLevel and record.level or level)
        end
    end
    if self.fishingChatGuard then self.fishingChatGuard:SetAttribute("chat-owned",nil) end
    state.root:Hide()
    self.fishingChatState=nil; self.fishingChatRestorePending=nil; self.fishingChatReleasing=nil
end
function FF:InstallFishingChatHooks()
    if not hooksecurefunc then return end
    self.fishingChatHooks=self.fishingChatHooks or {}
    for _,name in ipairs({"FCF_OpenNewWindow","FCF_OpenTemporaryWindow","FCF_DockFrame","FCF_UnDockFrame"}) do
        if type(_G[name])=="function" and not self.fishingChatHooks[name] then
            self.fishingChatHooks[name]=true
            hooksecurefunc(name,function() self:SyncFishingChatVisibility() end)
        end
    end
    if ChatFrameUtil and type(ChatFrameUtil.ActivateChat)=="function" and not self.fishingChatHooks.activate then
        self.fishingChatHooks.activate=true
        hooksecurefunc(ChatFrameUtil,"ActivateChat",function(editBox)
            local state=self.fishingChatState
            if not state or state.releasing or not editBox or editBox.disableActivate or not Under(editBox,state.root) then return end
            self:RevealFishingChat()
            -- Activation is a deliberate native chat action, never a message
            -- event. Do not steal focus when an incoming whisper reveals chat.
            if not Combat() and editBox:IsShown() and not editBox:HasFocus() and not self.fishingChatFocusing then
                self.fishingChatFocusing=true; editBox:SetFocus(); self.fishingChatFocusing=nil
            end
        end)
    end
end
function FF:SyncFishingChatVisibility(hiding)
    if self.fishingChatChanging or self.fishingChatReleasing then return end
    local mode=self:GetFishingChatMode()
    local active=mode~="hidden" and self:GetBlizzardUIHideMode()~="never"
        and self.bar and self.bar:IsShown() and not self.fishingUIManualOverride
        and (hiding or self.fishingUIHiddenByAddon) and UIParent and (hiding or not UIParent:IsShown())
    local state=self.fishingChatState
    if not active or self.fishingChatRestorePending then
        self:ReleaseFishingChat(); state=self.fishingChatState
        if not active or state then return end
    end
    if Combat() then
        if state then self:RevealFishingChat() end
        return
    end
    self.fishingChatChanging=true
    if not state then
        local root=self.fishingChatRoot or CreateFrame("Frame",nil,self.visibilityRoot,"SecureHandlerBaseTemplate")
        root:SetAllPoints(UIParent); root:EnableMouse(false)
        local events=self.fishingChatEvents or CreateFrame("Frame",nil,self.visibilityRoot)
        self.fishingChatRoot,self.fishingChatEvents=root,events
        if not self.fishingChatGuard and RegisterStateDriver then
            local guard=CreateFrame("Frame",nil,self.visibilityRoot,"SecureHandlerStateTemplate")
            guard:SetFrameRef("chat",root)
            guard:SetAttribute("_onstate-combat",[[
                if newstate=="combat" and self:GetAttribute("chat-owned") then
                    self:GetFrameRef("chat"):Show()
                    self:GetFrameRef("chat"):SetAlpha(1)
                end
            ]])
            if pcall(RegisterStateDriver,guard,"combat","[combat]combat;peace") then self.fishingChatGuard=guard end
        end
        if self.fishingChatGuard then self.fishingChatGuard:SetAttribute("chat-owned",true) end
        local members=Roots()
        local interacting=Interacting({members=members,root=root})
        state={root=root,events=events,frames={},members=members,untilTime=interacting and GetTime()+12 or 0,mode=mode}
        if mode=="always" or interacting then root:SetAlpha(1); root:Show()
        else root:Hide(); root:SetAlpha(0) end
        self.fishingChatState=state
        events:SetScript("OnEvent",function(_,event)
            if event=="PLAYER_REGEN_ENABLED" then
                state.untilTime=GetTime()+12; self:SyncFishingChatVisibility()
            elseif event=="PLAYER_REGEN_DISABLED" then self:RevealFishingChat()
            elseif event=="ADDON_LOADED" then self:SyncFishingChatVisibility()
            else self:RevealFishingChat() end
        end)
        if not self.fishingChatBarHook then
            self.fishingChatBarHook=true
            self.bar:HookScript("OnHide",function() self:ReleaseFishingChat() end)
        end
    end
    local changed=state.mode~=mode
    state.mode=mode; state.releasing=nil
    state.events:UnregisterAllEvents()
    state.events:RegisterEvent("PLAYER_REGEN_DISABLED"); state.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    state.events:RegisterEvent("ADDON_LOADED")
    if mode~="always" then
        for _,event in ipairs(WHISPERS) do state.events:RegisterEvent(event) end
        if mode=="guild" then state.events:RegisterEvent("CHAT_MSG_GUILD") end
    end
    state.members=Roots()
    for _,frame in ipairs(state.members) do
        if not state.frames[frame] and Under(frame,UIParent) then
            local record={parent=frame:GetParent(),scale=frame:GetScale(),strata=frame:GetFrameStrata(),level=frame:GetFrameLevel()}
            record.appliedScale=frame:GetEffectiveScale()/state.root:GetEffectiveScale()
            state.frames[frame]=record
            frame:SetParent(state.root); frame:SetScale(record.appliedScale)
            record.appliedScale=frame:GetScale()
            frame:SetFrameStrata(record.strata); frame:SetFrameLevel(record.level)
            record.appliedStrata,record.appliedLevel=frame:GetFrameStrata(),frame:GetFrameLevel()
        end
    end
    self:InstallFishingChatHooks()
    if changed then state.untilTime=0 end
    if mode=="always" then
        state.root:SetAlpha(1); state.root:Show(); state.root:SetScript("OnUpdate",nil)
    elseif Interacting(state) then self:RevealFishingChat()
    elseif GetTime()<state.untilTime or (not changed and state.root:IsShown()) then
        state.root:Show(); state.root:SetScript("OnUpdate",function(_,elapsed) self:PaintFishingChat(elapsed) end)
    else state.root:Hide(); state.root:SetAlpha(0); state.root:SetScript("OnUpdate",nil) end
    self.fishingChatChanging=nil
end
