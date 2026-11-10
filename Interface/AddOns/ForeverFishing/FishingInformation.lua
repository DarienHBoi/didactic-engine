-- Forever Fishing
-- Copyright Â© 2026 Hamish336. All Rights Reserved.
-- Applies to original Forever Fishing code and assets only.
-- Blizzard-owned assets and trademarks remain property of Blizzard Entertainment.
-- Unauthorized redistribution or modification is prohibited.
local FF = _G.ForeverFishing
-- Removed development status/seconds fields are ignored; no preference reset.
local FIELDS={enabled=true,skill=true,progress=true}
function FF:GetFishingInformationOptions()
    local saved=self.db and self.db.fishingInformation
    local out={}
    for key in pairs(FIELDS) do out[key]=not (type(saved)=="table" and saved[key]==false) end
    local mode=type(saved)=="table" and saved.progressMode
    -- Explicit mode wins; the old boolean retains its equivalent default.
    out.progressMode=(mode=="off" or mode=="always" or mode=="hidden") and mode or (out.progress and "always" or "off")
    out.progress=out.progressMode~="off"
    return out
end
function FF:SetFishingCastProgressMode(mode)
    if not self.db or (mode~="off" and mode~="always" and mode~="hidden") then return false end
    if type(self.db.fishingInformation)~="table" then self.db.fishingInformation={} end
    self.db.fishingInformation.progressMode=mode
    self.db.fishingInformation.progress=mode~="off"
    self:ApplyFishingInformationLayout()
    if self.settingsPanel and self.settingsPanel.RefreshInformationControls then self.settingsPanel:RefreshInformationControls() end
    return true
end
function FF:SetFishingInformationOption(key,value)
    if not FIELDS[key] or not self.db then return false end
    if key=="progress" then return self:SetFishingCastProgressMode(value==true and "always" or "off") end
    if type(self.db.fishingInformation)~="table" then self.db.fishingInformation={} end
    self.db.fishingInformation[key]=value==true
    self:ApplyFishingInformationLayout()
    if self.settingsPanel and self.settingsPanel.RefreshInformationControls then self.settingsPanel:RefreshInformationControls() end
    return true
end
function FF:InitializeFishingInformation()
    local saved=self.db and self.db.fishingInformation
    if type(saved)=="table" then saved.progressMode=self:GetFishingInformationOptions().progressMode end
    local button=self.castButton
    -- Keep the original heading anchor/font; reserve the native seconds area.
    button.label:SetWidth(244); button.label:SetJustifyH("LEFT"); button.label:SetWordWrap(false)
    local seconds=button:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    seconds:SetPoint("TOPRIGHT",button,"TOPRIGHT",-35,-16); seconds:SetWidth(65); seconds:SetJustifyH("RIGHT")
    seconds:SetTextColor(.9,.8,.55); button.fishingSeconds=seconds
    local track=button:CreateTexture(nil,"ARTWORK")
    track:SetPoint("BOTTOMLEFT",button,"BOTTOMLEFT",10,4); track:SetSize(418,3); track:SetColorTexture(.24,.19,.12,.8)
    local fill=button:CreateTexture(nil,"OVERLAY")
    fill:SetPoint("BOTTOMLEFT",track,"BOTTOMLEFT"); fill:SetSize(1,3); fill:SetColorTexture(.8,.61,.28,.95)
    button.fishingProgressTrack,button.fishingProgressFill=track,fill
    self:ApplyFishingInformationLayout()
end
function FF:ApplyFishingInformationLayout()
    if not self.castButton or not self.castButton.fishingSeconds then return end
    if InCombatLockdown and InCombatLockdown() then self.fishingInformationPending=true; return end
    self.fishingInformationPending=nil
    local options=self:GetFishingInformationOptions()
    if self.minimalCastGuard then self.minimalCastGuard:SetAttribute("restore-information",options.enabled) end
    local opacity=self.GetFishingHUDOpacity and self:GetFishingHUDOpacity() or 1
    local shown=options.enabled and opacity>0
    -- Keep the session and secure Close forwarding target alive. All panel
    -- controls become invisible and input-transparent together.
    local owner=GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()
    for _,field in ipairs({"castButton","bindButton","closeButton"}) do
        local control=self[field]
        if control then
            control:SetAlpha(shown and opacity or 0)
            control:EnableMouse(shown and opacity==1 or false)
            if not shown and owner==control then GameTooltip:Hide() end
        end
    end
    self.castButton.hint:SetShown(shown)
    if not shown then self.castButton.statusIcon:Hide() end
    self.castButton.label:SetShown(shown)
    self:UpdateFishingInformation(true)
end
-- Presentation only. Unknown caps/levels never imply training eligibility.
function FF:GetFishingInformationSkillText(skill,level)
    if not skill or not skill.base then return "Forever Fishing" end
    local base,cap=tonumber(skill.base),tonumber(skill.trainedCap)
    local rank=self.fishingRankInfo and self.fishingRankInfo[cap]
    if not base or not rank then
        return self:LocalizedText("information.skill-format",self:FishingName(),skill.base,tostring(cap or "?"))
    end
    if cap==300 and base==300 then return self:LocalizedText("information.expert-angler") end
    local nextRank=self.fishingRankInfo[rank.nextCap]
    local eligible=nextRank and base>=nextRank.minSkill and (tonumber(level) or 0)>=nextRank.minLevel
    local capped=eligible and base>=cap
    local label=self:LocalizedText("information.rank-format",
        self:LocalizedText("information.rank."..string.lower(rank.name)),base,
        eligible and not capped and "*" or "",cap,capped and "!" or "")
    local tip=eligible and self:LocalizedText(capped and "information.train-capped" or "information.train-available",
        self:LocalizedText("information.rank."..string.lower(nextRank.name))) or nil
    return label,tip
end
function FF:UpdateFishingInformation(refreshSkill,playerLevel)
    local button=self.castButton
    if not button or not button.fishingSeconds then return end
    local options=self:GetFishingInformationOptions()
    if self.SyncMinimalFishingView then self:SyncMinimalFishingView() end
    local enabled=options.enabled and (not self.GetFishingHUDOpacity or self:GetFishingHUDOpacity()>0)
    if refreshSkill or not self.fishingInformationSkill then
        self.fishingInformationSkill=self.GetJournalSkills and self:GetJournalSkills().Fishing
        self.fishingInformationLevel=tonumber(playerLevel) or (UnitLevel and UnitLevel("player"))
        -- Refresh an already-hovered status tooltip only while it still owns it.
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()==button and GameTooltip:IsShown() then
            local enter=button:GetScript("OnEnter")
            if enter then enter(button) end
        end
    end
    button.label:SetShown(enabled)
    local skill=self.fishingInformationSkill
    if enabled and options.skill and skill and skill.base then
        button.label:SetText((self:GetFishingInformationSkillText(skill,self.fishingInformationLevel)))
    elseif enabled then button.label:SetText("Forever Fishing") end
    local active,remaining,fraction=self:GetFishingChannelProgress()
    local ownedHidden=self.fishingUIHiddenByAddon and UIParent and not UIParent:IsShown()
    local minimalShown=self.minimalFishingViewActive and self.minimalCastFrame and self.minimalCastFrame:IsShown()
    local progress=enabled and active and not minimalShown
        and (options.progressMode=="always" or (options.progressMode=="hidden" and ownedHidden))
    button.fishingSeconds:SetShown(progress and true or false)
    if active then button.fishingSeconds:SetText(FF:LocalizedText("format.display-seconds",FF:LocalizedNumber(remaining,1))) end
    button.fishingProgressTrack:SetShown(progress and true or false)
    button.fishingProgressFill:SetShown(progress and true or false)
    if progress then
        button.fishingProgressFill:SetWidth(math.max(.001,418*fraction))
        button.fishingProgressFill:SetShown(fraction>0)
    end
    local minimal=self.minimalCastFrame
    if minimal and self.minimalFishingViewActive and active then
        minimal.fill:SetWidth(math.max(.001,minimal.trackWidth*fraction))
        minimal.fill:SetShown(fraction>0)
    end
    if not enabled then
        button.hint:Hide(); button.statusIcon:Hide()
        local message=self.masterChefQuickStatus
        if message and message~=self.hiddenFishingInformationNotice and self.ShowPreparationStatusNotice then
            self:ShowPreparationStatusNotice(message,"chef")
        end
        self.hiddenFishingInformationNotice=message
    else
        button.hint:Show()
        button.statusIcon:SetShown(button.castStatusStyle and button.castStatusStyle.icon
            and not button.paintedChefOverlay and true or false)
        self.hiddenFishingInformationNotice=nil
    end
end
-- Both cast displays use the same live native channel bounds, including UPDATE.
function FF:GetFishingChannelProgress()
    local start,finish=tonumber(self.castStart),tonumber(self.castEnd)
    local active=self.active and start and finish and finish>start
    local remaining=active and math.max(0,finish-GetTime()) or 0
    return active,remaining,active and math.min(1,remaining/(finish-start)) or 0
end
function FF:AddFishingInformationTooltip()
    local skill=self.GetJournalSkills and self:GetJournalSkills().Fishing
    if skill and skill.base then
        GameTooltip:AddLine(FF:LocalizedText("information.skill-tooltip",skill.base,tostring(skill.trainedCap or "?"),skill.value or skill.base),.83,.72,.52,true)
        GameTooltip:AddLine(FF:LocalizedText("information.bonus-tooltip",(skill.value or skill.base)-skill.base),.76,.82,.8,true)
        local level=math.max(tonumber(UnitLevel and UnitLevel("player")) or 0,tonumber(self.fishingInformationLevel) or 0)
        local _,training=self:GetFishingInformationSkillText(skill,level)
        if training then GameTooltip:AddLine(training,.83,.72,.52,true) end
    end
end
