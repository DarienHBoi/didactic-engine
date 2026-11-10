-- Forever Fishing
-- Copyright © 2026 Hamish336. All Rights Reserved.
-- Applies to original Forever Fishing code and assets only.
-- Blizzard-owned assets and trademarks remain property of Blizzard Entertainment.
-- Unauthorized redistribution or modification is prohibited.
local FF = _G.ForeverFishing

-- Action IDs are separate from retired flyout assignments: a saved menu key
-- must never become a consumable-use key without a deliberate assignment.
local function L(key,...) return FF:LocalizedText(key,...) end
FF.fishingActions = {
    fishing = {labelKey="action.fishing",label=L("action.fishing"),target="ForeverFishingCastActionButton"},
    recast = {labelKey="action.recast",label=L("action.recast"),target="ForeverFishingQuickRecastButton"},
    gear = {labelKey="action.gear",label=L("action.gear"),target="ForeverFishingGearActionButton"},
    lure = {labelKey="action.lure",label=L("action.lure"),target="ForeverFishingLureActionButton"},
    ["chef-menu"] = {labelKey="action.chef",label=L("action.chef"),target="ForeverFishingChefFlyoutActionButton",method="ShowMasterChefQuickTray"},
    ["utility-menu"] = {labelKey="utility.open",label=L("utility.open"),target="ForeverFishingUtilityFlyoutActionButton",method="ShowUtilityPicker"},
    jump = {labelKey="action.jump",label=L("action.jump")},
    open = {labelKey="action.toggle",label=L("action.toggle"),target="ForeverFishingOpenControlsActionButton",scope="always"},
}
FF.fishingActionOrder={"fishing","recast","gear","lure","chef-menu","utility-menu","jump","open"}
function FF:InitializeFishingActionBindings()
    -- Retired development mode: the saved key is the only input preference.
    self.db.rightClickFishing=nil
    local keys=self.db.actionBindings
    if type(keys)=="table" then keys["gear-menu"]=nil; keys["lure-menu"]=nil end
end
function FF:RefreshFishingActionLanguage()
    for _,entry in pairs(self.fishingActions) do entry.label=L(entry.labelKey) end
end
function FF:GetFishingPreparationSummary()
    local kind=self.db.autoEquipGear and (self.db.autoEquipLures and "gear-lure" or "gear")
        or (self.db.autoEquipLures and "lure" or "cast")
    return L("preparation."..kind)..(self.db.cameraAssist and L("preparation.camera") or "")
end
function FF:GetFishingActionKey(action)
    if not self.db then return end
    if action=="fishing" then return self.db.key end
    local key=type(self.db.actionBindings)=="table" and self.db.actionBindings[action]
    return type(key)=="string" and key~="" and key or nil
end
function FF:GetFishingCaptureInstruction(action)
    return L(action=="fishing" and "binding.capture-fishing-prompt" or "binding.capture-prompt")
end
local function ReservedMouse(key)
    local base=key and key:gsub("ALT%-",""):gsub("CTRL%-",""):gsub("SHIFT%-","")
    return base=="BUTTON1" or base=="BUTTON2" or key=="BUTTON4"
end
function FF:GetFishingJumpState(action,candidate)
    local used={}
    for _,id in ipairs(self.fishingActionOrder) do
        if id~="jump" then
            local key=id==action and candidate or self:GetFishingActionKey(id)
            if id==action and candidate==nil then key=nil end
            if key then used[key]=true end
        end
    end
    local native={}
    if GetBindingKey then
        local ok,first,second=pcall(GetBindingKey,"JUMP")
        if ok then if first then native[#native+1]=first end; if second then native[#native+1]=second end end
    end
    local needed=false
    for _,key in ipairs(native) do if used[key] then needed=true end end
    local preferred=action=="jump" and candidate or self:GetFishingActionKey("jump")
    if action=="jump" and candidate==nil then preferred=nil end
    if preferred and not used[preferred] and not ReservedMouse(preferred) then return needed,preferred end
    local choices={"SHIFT-SPACE"}
    for _,key in ipairs(native) do choices[#choices+1]=key end
    for _,key in ipairs({"CTRL-SPACE","ALT-SPACE","CTRL-SHIFT-SPACE","ALT-SHIFT-SPACE","CTRL-J","ALT-J","SHIFT-J","CTRL-SHIFT-J","ALT-SHIFT-J","ALT-CTRL-J"}) do choices[#choices+1]=key end
    for _,key in ipairs(choices) do
        local assignment=GetBindingAction and GetBindingAction(key,true) or ""
        if not used[key] and not ReservedMouse(key) and (assignment=="" or assignment=="JUMP") then return needed,key end
    end
    -- As with an explicitly chosen fishing shortcut, an ordinary game action
    -- may be overridden temporarily. Prefer free/native Jump keys first, but
    -- never strand Jump merely because those game keys are already assigned.
    for _,key in ipairs(choices) do
        if not used[key] and not ReservedMouse(key) then return needed,key end
    end
    return needed,nil
end
function FF:FishingActionBindingConflict(action,key)
    if not key then
        if action=="jump" then local needed,fallback=self:GetFishingJumpState(action,nil);if needed and not fallback then return L("binding.jump-required") end end
        return
    end
    if not self.fishingActions[action] then return L("binding.unknown-action") end
    if key==self.doubleRightClickKey then
        if action=="fishing" then return end
        return L("binding.world-mouse")
    end
    if ReservedMouse(key) and not (action=="fishing" and key:match("BUTTON4$")) then return key:match("BUTTON4$") and L("binding.journal-back") or L("binding.world-mouse") end
    for _,id in ipairs(self.fishingActionOrder) do
        if id~=action and self:GetFishingActionKey(id)==key then return self.fishingActions[id].label,id end
    end
    local needed,fallback=self:GetFishingJumpState()
    local willNeed,willFallback=self:GetFishingJumpState(action,key)
    if action~="jump" and needed and fallback==key and willNeed then return L("action.jump"),"jump" end
    if willNeed and not willFallback then return L("binding.jump-required") end
    -- Native game assignments are intentionally overridden temporarily. Only
    -- our own actions and reserved UI/world inputs are assignment conflicts.
end
function FF:GetFishingGameBindingName(key)
    local assigned=GetBindingAction and GetBindingAction(key,true) or ""
    if assigned=="" then assigned=GetBindingAction and GetBindingAction(key) or "" end
    if assigned=="" then return end
    local label=_G["BINDING_NAME_"..assigned] or (GetBindingText and GetBindingText(assigned,"BINDING_NAME_"))
    if label and label~="" and label~=assigned then return label end
    local target=assigned:match("^CLICK ([^:]+):")
    if target then
        for _,entry in pairs(self.fishingActions) do if entry.target==target then return entry.label end end
        return L("binding.addon-shortcut")
    end
    return L("binding.game-shortcut")
end
function FF:ReviewFishingBinding(key)
    if not self.captureInputReady or not self.capture:IsShown() then return end
    local action=self.keyCaptureAction or "fishing"
    local conflict,other=self:FishingActionBindingConflict(action,key)
    self.captureCandidate,self.captureCanConfirm,self.captureConflictAction=key,nil,nil
    self.captureConfirm:Hide();self.captureCancel:Hide()
    self.captureInstruction:SetText(self:GetFishingCaptureInstruction(action))
    self.captureScope:SetText(action~="open" and self:LocalizedText("binding.session-only") or "")
    self.captureScope:SetTextColor(.80,.84,.84);self.captureDetail:SetText("")
    if conflict then
        self.captureDetail:SetText(other and L("binding.replace-conflict",self:GetFishingBindingLabel(key),conflict) or L("binding.conflict",conflict))
        if other then
            self.captureConflictAction=other;self.captureCanConfirm=true
            self.captureConfirm:SetText(L("binding.replace"))
        end
    elseif action=="open" then
        self.captureCanConfirm=true
        self.captureConfirm:SetText(L("binding.assign"))
        self.captureDetail:SetText(L("binding.global-candidate",self:GetFishingBindingLabel(key)))
    else self:FinishKeyCapture(key);return end
    if self.captureCanConfirm then
        if action=="open" or other=="open" then
            self.captureScope:SetText(L("binding.global-warning"))
            self.captureScope:SetTextColor(1,.84,.2)
            local assigned=self:GetFishingGameBindingName(key)
            if assigned then self.captureDetail:SetText(self.captureDetail:GetText().."\n"..L("binding.override-game",assigned)) end
        end
        self.captureConfirm:SetEnabled(true);self.captureConfirm:Show()
        if action~="open" and other~="open" then self.captureCancel:Show() end
    end
    self:LayoutFishingBindingCapture()
end
function FF:ReplaceFishingActionBinding(action,key,other)
    if not self.db or (InCombatLockdown and InCombatLockdown()) then return false end
    local _,current=self:FishingActionBindingConflict(action,key)
    -- The offer names one exact assignment. Never clear a newer/different one.
    if current~=other or not self.fishingActions[other] or action==other then return false end
    local oldKey=self.db.key
    local oldBindings=self.db.actionBindings
    local bindings={}
    if type(oldBindings)=="table" then for id,value in pairs(oldBindings) do bindings[id]=value end end
    self.db.actionBindings=bindings
    if other=="fishing" then self.db.key=nil else bindings[other]=nil end
    if action=="fishing" then self.db.key=key else bindings[action]=key end
    -- Validate the complete proposed state before any override/UI side effects.
    -- Replacing automatic Jump lets the existing resolver choose another chord.
    local conflict=self:FishingActionBindingConflict(action,key)
    if conflict then self.db.key,self.db.actionBindings=oldKey,oldBindings;return false,conflict end
    local ok,reason=self:SetFishingActionBinding(action,key)
    if not ok then self.db.key,self.db.actionBindings=oldKey,oldBindings;return false,reason end
    return true
end
function FF:SetFishingActionBinding(action,key)
    local entry=self.fishingActions[action]
    if not entry or (InCombatLockdown and InCombatLockdown()) then return false end
    local conflict=self:FishingActionBindingConflict(action,key)
    if conflict then return false,conflict end
    if action=="fishing" then self:SetKey(key)
    else
        self.db.actionBindings=type(self.db.actionBindings)=="table" and self.db.actionBindings or {}
        self.db.actionBindings[action]=key
        self:ApplyBindings();self:RefreshUI()
    end
    if self.settingsPanel and self.settingsPanel.RefreshBindingControls then self.settingsPanel:RefreshBindingControls() end
    return true
end
function FF:ApplyAdditionalFishingBindings(owner,globalOwner)
    for _,action in ipairs(self.fishingActionOrder) do
        local entry=self.fishingActions[action]
        local key=self:GetFishingActionKey(action)
        if action~="fishing" and action~="jump" and key and (self:IsFishingSessionOpen() or entry.scope=="always")
            and not self:FishingActionBindingConflict(action,key) then
            local target=action=="recast" and self.quickRecastButton or action=="gear" and self.gearButton
                or action=="lure" and self.lureButton or (self.fishingActionButtons and self.fishingActionButtons[action])
            if target then SetOverrideBindingClick(entry.scope=="always" and globalOwner or owner,true,key,entry.target,"LeftButton") end
        end
    end
    local needed,jump=self:GetFishingJumpState()
    if self:IsFishingSessionOpen() and needed and jump then pcall(SetOverrideBinding,owner,true,jump,"JUMP") end
end
function FF:ConfigureFishingToggleAction(close)
    local toggle=self.fishingActionButtons and self.fishingActionButtons.open
    if not toggle or not close then return end
    toggle:SetFrameRef("session",self.bar)
    toggle:SetAttribute("clickbutton1",close)
    if toggle.fishingToggleWrapped==true then return end
    toggle.fishingToggleWrapped=true
    SecureHandlerWrapScript(toggle,"OnClick",toggle,[[
        self:SetAttribute("type1",nil)
        if down then return false end
        if SecureCmdOptionParse("[combat]combat") then
            if self:GetFrameRef("session"):IsShown() then self:SetAttribute("type1","click") end
        end
    ]])
end

function FF:QuickRecastAllowed()
    if not self.db or not self:IsFishingSessionOpen() or self.journalInputFocus or self.settingsKeyboardFocus
        or self.captureCommitPending or (self.capture and self.capture:IsShown())
        or (InCombatLockdown and InCombatLockdown()) then return false end
    if UnitCastingInfo and UnitCastingInfo("player") then return false end
    -- Live native state wins over a delayed CHANNEL_START/STOP event. A Chef
    -- channel, lure or any other spell must never be stopped by this action.
    if UnitChannelInfo and UnitChannelInfo("player") and not self:IsFishingChannelActive() then return false end
    -- An already-issued gear operation must finish, but rotation preparation
    -- and timing/readiness never gate this explicit repositioning action.
    return not (self.pendingFishingGear or self.pendingGearRestore)
end

function FF:SyncQuickRecastAction()
    if not self.quickRecastButton or (InCombatLockdown and InCombatLockdown()) then return false end
    local name = self:FishingName()
    local allowed = self:QuickRecastAllowed()
    self.quickRecastButton:SetAttribute("type", allowed and "macro" or nil)
    -- Both commands are secure player input. No refresh, event or timer casts.
    self.quickRecastButton:SetAttribute("macrotext", "/stopcasting [nocombat,channeling:" .. name
        .. "]\n/cast [nocombat,nochanneling] " .. name)
    return allowed
end

function FF:CreateFishingActionControls(parent)
    local cast = CreateFrame("Button", "ForeverFishingCastActionButton", parent, "SecureActionButtonTemplate")
    cast:SetSize(1, 1)
    cast:SetPoint("TOPLEFT", parent, "TOPLEFT")
    cast:EnableMouse(false)
    cast:RegisterForClicks("AnyUp")
    cast:SetAttribute("useOnKeyDown", false)
    cast:SetScript("PreClick", function(button) self:OnCastButtonPreClick(button) end)
    cast:SetScript("PostClick", function() self:OnCastButtonPostClick() end)
    self.castActionButton = cast

    local recast = CreateFrame("Button", "ForeverFishingQuickRecastButton", parent, "SecureActionButtonTemplate")
    recast:SetSize(1, 1)
    recast:SetPoint("TOPLEFT", parent, "TOPLEFT")
    recast:EnableMouse(false)
    recast:RegisterForClicks("AnyUp")
    recast:SetAttribute("useOnKeyDown", false)
    recast:SetScript("PreClick", function()
        self.recastClickArmed = self:SyncQuickRecastAction()
        self.castClickInProgress = self.recastClickArmed or nil
    end)
    recast:SetScript("PostClick", function()
        self.castClickInProgress = nil
        if not self.recastClickArmed then return end
        self.recastClickArmed = nil
        -- Share only native SENT-event deduplication/sound bookkeeping.
        -- Never create a normal-rotation lock or wait for a successful channel;
        -- a rejected attempt leaves the next fresh input immediately eligible.
        self.lastCastButtonPressAt = GetTime()
        self:OnFishingSoundCastSent()
    end)
    self.quickRecastButton = recast
    self.fishingActionButtons = {}
    for _,id in ipairs({"open","chef-menu","utility-menu"}) do
        local entry=self.fishingActions[id]
        local button=CreateFrame("Button",entry.target,parent,id=="open" and "SecureActionButtonTemplate,SecureHandlerBaseTemplate" or nil)
        button:SetSize(1,1);button:SetPoint("TOPLEFT",parent,"TOPLEFT");button:EnableMouse(false)
        button:RegisterForClicks("AnyUp");button:SetAttribute("useOnKeyDown",false)
        button:SetScript(id=="open" and "PostClick" or "OnClick",function(_,_,down)
            if down or (InCombatLockdown and InCombatLockdown()) or self.journalInputFocus or self.settingsKeyboardFocus
                or (self.capture and self.capture:IsShown()) then return end
            if id=="open" then self:ToggleUI()
            elseif self:IsFishingSessionOpen() then self[entry.method](self) end
        end)
        self.fishingActionButtons[id]=button
    end
    -- This session-owned update frame survives hiding any status artwork.
    self.fishingUpdateFrame = CreateFrame("Frame", nil, parent)
end
