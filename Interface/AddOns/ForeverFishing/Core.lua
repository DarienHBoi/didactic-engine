-- Forever Fishing
-- Copyright © 2026 Hamish336. All Rights Reserved.
-- Applies to original Forever Fishing code and assets only.
-- Blizzard-owned assets and trademarks remain property of Blizzard Entertainment.
-- Unauthorized redistribution or modification is prohibited.
local addonName = ...
local FF = {}
_G.ForeverFishing = FF

local FISHING_SPELL = 131474
local FISHING_CAST = 131476
local MEDIA = "Interface\\AddOns\\ForeverFishing\\Media\\"
local ICON = MEDIA .. "Square"
local MACRO_NAME = "FF Fishing Cast"
local DEFAULT_FISHING_KEY = "SPACE"
-- Independent SavedVariables baselines. A public data-format change advances
-- only the data version; a public visual/settings reset advances only the UI version.
local DATA_SCHEMA_VERSION = 1
local UI_SCHEMA_VERSION = 5
local BACKGROUND_SOUND_CVAR = "Sound_EnableSoundWhenGameIsInBG"
local BOBBER_PROBE_SECONDS = 0.05
local MISSING_CONFIRM_SECONDS = 0.2
local OTHER_TARGET_SETTLE_SECONDS = 0.75
local OTHER_TARGET_CONFIRM_SECONDS = 0.3
local UNKNOWN_TARGET_SETTLE_SECONDS = 1
local SOFT_BOBBER_CONFIRM_SECONDS = 0.3
local BIND_OWNER = CreateFrame("Frame", nil, WorldFrame, "SecureHandlerBaseTemplate")
local INTERACT_OWNER = CreateFrame("Frame", nil, WorldFrame, "SecureHandlerBaseTemplate")
local GLOBAL_BIND_OWNER
local events = CreateFrame("Frame", nil, WorldFrame)

FF.icon = ICON
FF.roundIcon = MEDIA .. "Round"
FF.lureIcon = MEDIA .. "LureNoBoarder"
FF.castbarIcon = MEDIA .. "Castbar"
FF.fishingGearIcon = MEDIA .. "Buttons\\FishingGear"
FF.fishingGearPurchaseIcon = MEDIA .. "Buttons\\FishingRodPurchase"
FF.lurePurchaseIcon = MEDIA .. "Buttons\\PurchaseLure"
FF.journalIcon = MEDIA .. "Buttons\\Journal"
FF.settingsIcon = MEDIA .. "Buttons\\Settings"
FF.doubleRightClickKey = "DOUBLE_RIGHT_CLICK"

-- Public UI upgrades reset replaceable settings only. Gear/lure choices,
-- launcher layout, temporary CVar ownership records, and every earned fishing
-- record stay in the existing SavedVariables table.
local UI_SCHEMA_RESET_KEYS = {
    "key", "keyInitialized", "actionBindings", "language", "showMinimapIcon", "interactAssist", "soundFocus", "soundFocusVolumes", "hideLureGlowWhenOutOfLures",
    "autoEquipGear", "autoEquipLures", "manualGearAndLures", "autoOpenFishingBar",
    "autoRestoreGear", "journalFaction", "campMilestones", "fastAutoLoot", "catchRecap",
    "hideBlizzardUIWhileFishing", "blizzardUIHideMode", "fishingChatMode", "showFishingMinimap", "minimalFishingCastView",
    "position", "toolsPosition", "barScale", "toolsScale", "catchRecapPosition",
    "windowLayouts", "journalTextScale", "iconBarSpacing", "fishingBarMode", "lastCompactBarMode", "fishingBarOrientation", "fishingBarAutoCollapse", "flyoutGrid", "fishingInformation", "showUtilityButton", "utilityItems", "utilityHidden", "utilitySelectedItem", "flyoutLayouts", "flyoutDefaults",
    "layoutCoordinateVersion", "toolsIconCountVersion", "settingsLayoutVersion",
    "rangeSound", "rangeSoundLoop", "recastReminderSound", "recastReminderLoop",
    "recastReminderDelay", "catchConfirmedSound", "fishEscapedSound", "cookingCompleteSound",
    "enableAlertSounds", "soundRepeatInterval", "voiceVolume", "voiceVolumeDefaultVersion",
    "channelSound",
    "cameraAssist", "cameraModeDefaultsVersion", "cameraProfile", "cameraCloseScan",
    "cameraScanProfiles", "cameraSmartCloseLinkVersion", "cameraSavedView",
    "cameraSavedViewRecordVersion", "cameraFishingView", "cameraSmartBaseView",
    "cameraScanSpeed", "cameraSweepReach", "cameraSweepSpacing", "cameraSweepZoom",
    "cameraSweepTilt", "cameraSweepRows", "cameraSweepStart", "cameraPyramidStep",
    "cameraViewSlot", "cameraViewDelay", "cameraSmartAdjustment", "cameraSmartOffset",
    "cameraSmartTrigger", "cameraSmartSecondTrigger", "cameraSmartSecondOffset",
    "cameraMarkerHeight", "cameraMarkerStyle", "cameraMarkerStyleVersion",
    "cameraPyramidPath", "cameraRoundedTurns", "cameraRoundedDevOnly",
    "cameraRacetrackTurns", "cameraScanLogging", "cameraNativeCenter",
    "rangeDelay", "recastDelay", "hookDelay", "pressLock", "recastTimings", "cameraTimings",
    "timingDefaultsVersion", "cameraRecastDefaultsVersion", "cameraHookDefaultsVersion",
}

function FF:InitializeSavedVariableSchemaVersions(hadSavedState)
    local db = self.db
    if hadSavedState == nil then hadSavedState = next(db) ~= nil end
    if type(db.dataSchemaVersion) ~= "number" then
        db.dataSchemaVersion = DATA_SCHEMA_VERSION
    end
    local priorUI = db.uiSchemaVersion
    if type(priorUI) == "number" and priorUI >= UI_SCHEMA_VERSION then return end
    if hadSavedState then
        for _, key in ipairs(UI_SCHEMA_RESET_KEYS) do db[key] = nil end
    end
    db.uiSchemaVersion = UI_SCHEMA_VERSION
    return true -- Fresh settings or the existing public settings-reset boundary.
end

function FF:GetJournalFaction()
    local choice = self.db and self.db.journalFaction
    if choice == "Alliance" or choice == "Horde" then return choice end
    local playerFaction = UnitFactionGroup and UnitFactionGroup("player")
    return playerFaction == "Horde" and "Horde" or "Alliance"
end

function FF:SetJournalFaction(choice)
    if choice ~= "Auto" and choice ~= "Alliance" and choice ~= "Horde" then return end
    if self.db.journalFaction == choice then return end
    self.db.journalFaction = choice
    local settings = self.settingsPanel
    if settings and settings.journalFactionButton then settings.journalFactionButton:Refresh() end
    local journal = self.journalPanel
    if journal and journal:IsShown() and self.SelectJournalTab then
        self:SelectJournalTab(self.journalTab or "catch")
    end
end

function FF:GetFishingMinimapSnapshot()
    if not self.db then return {} end
    local lines = {}
    local session = self.session
    if session and type(session.casts) == "number" and type(session.catches) == "number" then
        lines[#lines + 1] = FF:LocalizedText("minimap.session", session.catches, session.casts)
        if self.CurrentSessionSeconds then
            local seconds = math.floor(self:CurrentSessionSeconds())
            lines[#lines + 1] = FF:LocalizedText("minimap.rod-time", math.floor(seconds / 3600), math.floor(seconds / 60) % 60)
        end
    end
    local lifetime = self.db.lifetime
    if lifetime and type(lifetime.catchCount) == "number" then lines[#lines + 1] = FF:LocalizedText("minimap.lifetime", lifetime.catchCount) end
    local location = self.GetFishingLocation and self:GetFishingLocation()
    if location then lines[#lines + 1] = FF:LocalizedText("minimap.location", location) end
    local equipped = self.FishingRodEquippedNow and self:FishingRodEquippedNow()
    if equipped == true then
        local itemID = GetInventoryItemID and GetInventoryItemID("player", 16)
        local name = itemID and GetItemInfo and GetItemInfo(itemID)
        lines[#lines + 1] = FF:LocalizedText("minimap.pole", name or FF:LocalizedText("minimap.equipped"))
        local seconds = self:LureSeconds()
        lines[#lines + 1] = seconds and seconds > 0 and FF:LocalizedText("minimap.lure-time", math.floor(seconds / 60), math.floor(seconds) % 60)
            or seconds == 0 and FF:LocalizedText("minimap.lure-none") or FF:LocalizedText("minimap.lure-unavailable")
    elseif equipped == false then lines[#lines + 1] = FF:LocalizedText("minimap.pole-none") end
    if self.db.lure then
        local name = GetItemInfo and GetItemInfo(self.db.lure)
        lines[#lines + 1] = FF:LocalizedText("minimap.selected-lure", name or self:LocalizedText("common.item-id",self.db.lure))
    end
    return lines
end

local function ShowFishingMinimapTooltip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("Forever Fishing", 1, 0.82, 0)
    GameTooltip:AddLine(FF:LocalizedText("minimap.open"), 0.85, 0.85, 0.85)
    GameTooltip:AddLine(FF:LocalizedText("minimap.settings"), 0.85, 0.85, 0.85)
    for _, line in ipairs(FF:GetFishingMinimapSnapshot()) do GameTooltip:AddLine(line, 0.94, 0.9, 0.77, true) end
    GameTooltip:Show()
end

function FF:UpdateLauncherIndividualIcon(launcher)
    local entry = launcher.addons and launcher.addons.ForeverFishing
    local button = entry and entry.generatedButton
    local icon = button and button.icon
    if icon then
        icon:SetTexture(self.roundIcon)
        icon:SetTexCoord(0, 1, 0, 1)
    end
    -- Customize only our generated icon; the canonical shared launcher keeps
    -- ownership of its click, drag, visibility and family-list behavior.
    if button and button:GetScript("OnEnter") ~= ShowFishingMinimapTooltip then
        button:SetScript("OnEnter", ShowFishingMinimapTooltip)
    end
end

function FF:SyncMinimapIconVisibility()
    local launcher = _G.ForeverAddonLauncher
    if launcher and type(launcher.SetIconVisible) == "function" then
        return launcher:SetIconVisible("ForeverFishing", self.db.showMinimapIcon ~= false)
    end
    -- A newer embedded implementation may have a different API. Never hide
    -- the shared family button or another addon's icon as a fallback.
    return false
end

function FF:SetMinimapIconShown(shown)
    local launcher = _G.ForeverAddonLauncher
    if not launcher or type(launcher.SetIconVisible) ~= "function" then
        self:Print(FF:LocalizedText("runtime.minimap-incompatible"))
        return false
    end
    self.db.showMinimapIcon = shown == true
    self:SyncMinimapIconVisibility()
    if self.settingsPanel then self.settingsPanel.minimapIconButton:SetState(self.db.showMinimapIcon) end
    return true
end

FF.session = {} -- Initialized from Statistics.lua after SavedVariables are ready.
FF.active = false
FF.recastReady = false
FF.recastWindow = false
FF.hookReady = false
FF.lastChannelEnd = 0
FF.recentTransitions = {}
FF.timing = { rangeMin = 0.05, rangeMax = 1.5, rangeDefault = 0.05,
    recastMin = 0.1, recastMax = 4, recastDefault = 0.2,
    hookMin = 0.1, hookMax = 4, hookDefault = 0.2,
    pressMin = 0, pressMax = 1.5, pressDefault = 0.25 }
FF.rangeSoundChoices = {
    { id = "off", label = "Off", labelKey = "sound.off" },
    { id = "soft", label = "Battle.net notification", labelKey = "sound.soft", kit = "UI_BNET_TOAST", fallback = 18019 },
    { id = "ping", label = "Soft ping", labelKey = "sound.ping", kit = "MAP_PING", fallback = 3175 },
    { id = "chime", label = "Chime", labelKey = "sound.chime", kit = "ALARM_CLOCK_WARNING_3", fallback = 12889 },
    { id = "raid", label = "Raid warning", labelKey = "sound.raid", kit = "RAID_WARNING", fallback = 8959 },
    { id = "male", label = "Male Voice", labelKey = "sound.male", voice = "male", singleRangePreview = true },
    { id = "female", label = "Female Voice", labelKey = "sound.female", voice = "female", singleRangePreview = true },
}

local function ClampTenth(value, minimum, maximum, default)
    value = tonumber(value) or default
    if value ~= value then value = default end
    return math.floor(math.max(minimum, math.min(maximum, value)) * 10 + 0.5) / 10
end

local function ClampTwentieth(value, minimum, maximum, default)
    value = tonumber(value) or default
    if value ~= value then value = default end
    return math.floor(math.max(minimum, math.min(maximum, value)) * 20 + 0.5) / 20
end

-- Keep the flat timing fields as the active profile for the existing cast
-- state machine. Each mode owns its saved sliders independently.
function FF:SaveTimingProfile()
    local key = self.db.cameraAssist and "cameraTimings" or "recastTimings"
    local profile = self.db[key]
    if type(profile) ~= "table" then profile = {}; self.db[key] = profile end
    for _, field in ipairs({ "rangeDelay", "recastDelay", "hookDelay", "pressLock" }) do
        profile[field] = self.db[field]
    end
end

function FF:ActivateTimingProfile()
    local profile = self.db[self.db.cameraAssist and "cameraTimings" or "recastTimings"]
    if type(profile) ~= "table" then self:InitializeTimingProfiles(); return end
    for _, field in ipairs({ "rangeDelay", "recastDelay", "hookDelay", "pressLock" }) do
        self.db[field] = profile[field]
    end
end

function FF:InitializeTimingProfiles()
    local timing = self.timing
    if type(self.db.recastTimings) ~= "table" then
        -- Existing adjustments belong to the original recast rotation.
        self.db.recastTimings = { rangeDelay = self.db.rangeDelay, recastDelay = self.db.recastDelay,
            hookDelay = self.db.hookDelay, pressLock = self.db.pressLock }
    end
    if type(self.db.cameraTimings) ~= "table" then self.db.cameraTimings = {} end
    if self.db.cameraRecastDefaultsVersion ~= 1 then
        if tonumber(self.db.cameraTimings.recastDelay) == 1 then self.db.cameraTimings.recastDelay = 0.6 end
        self.db.cameraRecastDefaultsVersion = 1
    end
    if self.db.cameraHookDefaultsVersion ~= 1 then
        if tonumber(self.db.cameraTimings.hookDelay) == 1 then self.db.cameraTimings.hookDelay = 0.6 end
        self.db.cameraHookDefaultsVersion = 1
    end
    for _, key in ipairs({ "recastTimings", "cameraTimings" }) do
        local profile = self.db[key]
        local camera = key == "cameraTimings"
        profile.rangeDelay = camera and 0.2 or ClampTwentieth(profile.rangeDelay, timing.rangeMin, timing.rangeMax, timing.rangeDefault)
        profile.recastDelay = ClampTenth(profile.recastDelay, timing.recastMin, timing.recastMax, camera and 0.6 or timing.recastDefault)
        profile.hookDelay = ClampTenth(profile.hookDelay, timing.hookMin, timing.hookMax, camera and 0.6 or timing.hookDefault)
        profile.pressLock = ClampTwentieth(profile.pressLock, timing.pressMin, timing.pressMax, timing.pressDefault)
    end
    self:ActivateTimingProfile()
end

function FF:ResetTimingProfiles()
    self.db.recastTimings, self.db.cameraTimings = nil, nil
    self.db.rangeDelay, self.db.recastDelay = self.timing.rangeDefault, self.timing.recastDefault
    self.db.hookDelay, self.db.pressLock = self.timing.hookDefault, self.timing.pressDefault
    self:InitializeTimingProfiles()
end

function FF:SetRapidPressLock(value)
    if InCombatLockdown and InCombatLockdown() then return false end
    if issecretvalue and issecretvalue(value) then return false end
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return false end
    self.db.pressLock = ClampTwentieth(value, self.timing.pressMin, self.timing.pressMax, self.timing.pressDefault)
    self:SaveTimingProfile()
    self:ApplyBindings()
    if self.SyncCastAction then self:SyncCastAction() end
    return true
end

function FF:CameraRecastReady()
    return self.db.cameraAssist and self.active and self.bobberCheckStartedAt
        and GetTime() - self.bobberCheckStartedAt >= (self.currentRecastDelay or self.db.recastDelay) or false
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(id)
        if name then return name end
    end
    if GetSpellInfo then return GetSpellInfo(id) end
end

-- Native recognition is independent of the selected addon language. Read
-- actual client names/identities; never translate a recognition key or action.
local function NativeText(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and not (issecretvalue and issecretvalue(value)) and type(value)=="string" and value~="" then return value end
end

function FF:GetNativeProfessionName(skillLineID, canonical)
    if skillLineID==356 then return self:FishingName() end
    local api=C_TradeSkillUI
    local name=NativeText(api and api.GetTradeSkillDisplayName,skillLineID)
    if name then return name end
    if GetProfessions and GetProfessionInfo then
        local ok,a,b,c,d,e,f=pcall(GetProfessions)
        if ok then
            local indices={a,b,c,d,e,f}
            for slot=1,6 do
                local index=indices[slot]
                if not (issecretvalue and issecretvalue(index)) and type(index)=="number" then
                    local valid,value,_,_,_,_,_,id=pcall(GetProfessionInfo,index)
                    if valid and not (issecretvalue and (issecretvalue(id) or issecretvalue(value)))
                        and id==skillLineID and type(value)=="string" and value~="" then return value end
                end
            end
        end
    end
    if skillLineID==185 then
        return NativeText(C_Spell and C_Spell.GetSpellName,2550) or NativeText(GetSpellInfo,2550) or canonical
    end
    return canonical
end

function FF:GetNativeErrorName(errorID)
    if issecretvalue and issecretvalue(errorID) then return end
    if type(errorID)~="number" or errorID<=0 or errorID>=math.huge or errorID~=math.floor(errorID) then return end
    return NativeText(GetGameMessageInfo,errorID)
end

function FF:MatchesNativeError(message, names, errorID)
    if issecretvalue and issecretvalue(message) then return false end
    if type(message)~="string" then return false end
    local identity=self:GetNativeErrorName(errorID)
    for _,name in ipairs(names) do
        if identity==name then return true end
        -- Retain native text fallback for custom/client-specific error identities.
        do
            local native=_G[name]
            if not (issecretvalue and issecretvalue(native)) and type(native)=="string" and native~="" then
                if message==native then return true end
                local pattern, fields=native:gsub("%%%d*%$?[sd]","\001")
                if fields>0 then
                    pattern=pattern:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1"):gsub("\001",".+")
                    if message:match("^"..pattern.."$") then return true end
                end
            end
        end
    end
    return false
end

function FF:FishingName()
    if GetProfessions and GetProfessionInfo then
        local _, _, _, fishing = GetProfessions()
        if fishing then
            local name = GetProfessionInfo(fishing)
            if name and name ~= "" then return name end
        end
    end
    return SpellName(7620) or SpellName(FISHING_SPELL) or SpellName(FISHING_CAST) or _G.FISHING or "Fishing"
end

local function IsFishingChannel()
    if not UnitChannelInfo then return false end
    local name, _, _, started, ends, _, _, spellID = UnitChannelInfo("player")
    if not name then return false end
    if spellID == FISHING_SPELL or spellID == FISHING_CAST or name == FF:FishingName() then
        return true, tonumber(started) and started / 1000, tonumber(ends) and ends / 1000
    end
    return false
end

function FF:IsFishingChannelActive()
    return IsFishingChannel()
end

local function SafeOutOfCombat()
    return not InCombatLockdown or not InCombatLockdown()
end

function FF:Print(message)
    print("|cffffc947Forever Fishing|r: " .. message)
end

function FF:RangeSoundChoice(id)
    for _, choice in ipairs(self.rangeSoundChoices) do
        if choice.id == id then return choice end
    end
end

function FF:PlayRangeSound(id)
    self:PreviewFishingSound("range", id)
end

function FF:WarnRangeOnce()
    self:SyncRangeSound()
end

local function BindingAction(key)
    if key == FF.doubleRightClickKey then
        if not FF:DoubleClickArmed() then return "Double right click (waiting for first click)" end
        key = "BUTTON2"
    end
    if not key or not GetBindingAction then return "unknown" end
    local ok, action = pcall(GetBindingAction, key, true)
    return ok and action and action ~= "" and action or "none"
end

local function ReadCVar(name)
    if not GetCVar then return nil end
    local ok, value = pcall(GetCVar, name)
    return ok and value or nil
end

-- Unknown identity is not proof of an out-of-range bobber. In Camera Assist,
-- offer the ordinary cursor-controlled search only after a full quiet second;
-- leave Recast mode and immediate native Interact recognition unchanged.
local function UnknownBobberState(self, now, label)
    self.cameraSoftBobberSince = nil
    self.bobberUnknownSince = self.bobberUnknownSince or now
    if self.db.cameraAssist and SafeOutOfCombat() and self.bobberCheckStartedAt
        and now - self.bobberCheckStartedAt >= UNKNOWN_TARGET_SETTLE_SECONDS
        and now - self.bobberUnknownSince >= UNKNOWN_TARGET_SETTLE_SECONDS then
        return "unavailable", label
    end
    return "unknown", label
end

local function ConfirmSoftBobber(self, now, label)
    self.bobberUnknownSince = nil
    -- A one-sample native target must not hide/recenter an unfinished search.
    -- Verified cursor acquisition still wins immediately in CameraAssist.
    if self.cameraAssistNeeded and not (self.cameraCast and self.cameraCast.bobberLocated) then
        self.cameraSoftBobberSince = self.cameraSoftBobberSince or now
        if now - self.cameraSoftBobberSince < SOFT_BOBBER_CONFIRM_SECONDS then
            return "landing", "confirming bobber target"
        end
    else self.cameraSoftBobberSince = nil end
    return "bobber", label
end

-- Fishing bobbers are game objects. On the Forever beta, UnitExists can be
-- false even while a bobber is selectable. UnitGUID distinguishes the tested
-- close cast (Fishing Bobber GUID) from a tested unhookable long cast (nil).
function FF:BobberInteractState()
    if not self.active then return "idle", "none" end
    local now = GetTime()
    local elapsed = self.bobberCheckStartedAt and now - self.bobberCheckStartedAt or 0
    if elapsed < BOBBER_PROBE_SECONDS then
        return "landing", "checking bobber"
    end
    if not UnitGUID then return UnknownBobberState(self, now, "UnitGUID unavailable") end
    local ok, guid = pcall(UnitGUID, "softinteract")
    if not ok or (issecretvalue and issecretvalue(guid)) then
        self.bobberMissingSince = nil
        self.bobberBlockedSince = nil
        self.cameraSoftBobberSince = nil
        return UnknownBobberState(self, now, "target identity unavailable")
    end
    -- The ordinary bobber is identified without a second API call on every
    -- status sample. Read its name only for other possible bobber types.
    if type(guid) == "string" and guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") == "35591" then
        self.bobberMissingSince = nil
        self.bobberBlockedSince = nil
        -- One optional name read per login, only after the standard ID proves it.
        if not self.cameraBobberNameRead and self.RememberFishingBobberName then
            self.cameraBobberNameRead = true
            if type(UnitName) == "function" then
                local nameOK, bobberName = pcall(UnitName, "softinteract")
                if nameOK then self:RememberFishingBobberName(guid, bobberName) end
            end
        end
        -- Snapshot the native close-cast identity once, reusing this read.
        if not self.cameraAssistNeeded and self.cameraNativeReferenceCast ~= self.channelStartSerial
            and self.RecordNativeBobberReference then
            self:RecordNativeBobberReference(guid)
        end
        return ConfirmSoftBobber(self, now, "Fishing Bobber (35591)")
    end
    local name
    if UnitName then
        ok, name = pcall(UnitName, "softinteract")
        if not ok or (issecretvalue and issecretvalue(name)) then name = nil end
    end
    local label = name or (guid and "GUID available") or "none"
    -- A known NPC/player identity takes precedence over the name fallback.
    local nonGameObject = type(guid) == "string" and not guid:match("^GameObject%-")
    if not nonGameObject and self:IsFishingBobberName(name, true) then
        self.bobberMissingSince = nil
        self.bobberBlockedSince = nil
        return ConfirmSoftBobber(self, now, label)
    end
    self.cameraSoftBobberSince = nil
    -- An NPC can win soft targeting even when the bobber is closer. Confirm
    -- that it remains selected after the bobber has had time to land. Unknown
    -- game objects get a delayed Camera Assist fallback; their identity never
    -- establishes that a bobber was acquired or that it can be hooked.
    if nonGameObject then
        self.bobberUnknownSince = nil
        self.bobberMissingSince = nil
        self.bobberBlockedSince = self.bobberBlockedSince or now
        if elapsed >= math.max(self.currentRangeDelay or self.db.rangeDelay, OTHER_TARGET_SETTLE_SECONDS)
            and now - self.bobberBlockedSince >= OTHER_TARGET_CONFIRM_SECONDS then
            return "blocked", label
        end
        return "landing", "waiting for bobber target"
    end
    self.bobberBlockedSince = nil
    if not guid then
        self.bobberUnknownSince = nil
        self.bobberMissingSince = self.bobberMissingSince or now
        local rangeDelay = self.currentRangeDelay or self.db.rangeDelay
        local confirmSeconds = math.min(MISSING_CONFIRM_SECONDS, math.max(BOBBER_PROBE_SECONDS, rangeDelay - BOBBER_PROBE_SECONDS))
        if elapsed < rangeDelay or now - self.bobberMissingSince < confirmSeconds then
            return "landing", "confirming no target"
        end
        return "missing", "none"
    end
    self.bobberMissingSince = nil
    return UnknownBobberState(self, now, label)
end

function FF:TraceTransition(message)
    local entries = self.recentTransitions
    entries[#entries + 1] = { at = GetTime(), message = message }
    if #entries > 8 then table.remove(entries, 1) end
end

function FF:GetFishingCastButton()
    return self.castActionButton or self.castButton
end

function FF:IsFishingSessionOpen()
    return self.bar and self.bar:IsShown() or false
end

function FF:BindingMode()
    if self:CastInputLocked() then return "rapid press lock" end
    if not self.active then return "cast" end
    if self.db.cameraAssist and self.cameraAssistNeeded then
        if self.cameraAssistBobber and self.hookReady then return "camera mouseover" end
        if self:CameraRecastReady() then return "camera recast" end
        return self.cameraCast and self.cameraCast.bobberLocated and "camera waiting for cursor" or "camera scan"
    end
    if self.db.cameraAssist and self.recastReady then return "native bobber recast" end
    if self.db.cameraAssist and self.recastWindow then return "good cast recast" end
    return self.nativeBobberReady and (not self.db.cameraAssist or self.hookReady) and "interact" or "settling"
end

function FF:ShowTrace()
    local channel, _, ends = IsFishingChannel()
    local remaining = channel and ends and string.format("%.1fs", math.max(0, ends - GetTime())) or "none"
    local traceSnapshot = self:CaptureFishingTraceSnapshot()
    local bobberState, bobberTarget = traceSnapshot.soft.state, traceSnapshot.soft.name or traceSnapshot.soft.identity
    local lureEntry
    for _, entry in ipairs(self.availableLures or {}) do
        if entry.id == self.db.lure then lureEntry = entry; break end
    end
    local lureButton = self.lureButton
    local lureMacro = lureButton and lureButton:GetAttribute("macro1")
    local lureBody = lureMacro and GetMacroBody and GetMacroBody(lureMacro)
    local castSlot = self:GetFishingCastButton() and self:GetFishingCastButton():GetAttribute("macro")
    local lines = {
        "Forever Fishing trace",
        self:FishingTraceEnvironment(),
        "Key: " .. (self.db.key or "none"),
        "Fishing bar: " .. (self.bar and self.bar:IsShown() and "open" or "closed"),
        "Fishing mode: " .. (self.db.cameraAssist and "Camera-assisted backup" or "Native bobber interaction"),
        "Key action: " .. self:BindingMode(),
        "Actual key binding: " .. BindingAction(self.db.key),
        "Cast macro: button slot " .. tostring(castSlot) .. "; verified slot " .. tostring(self:CastMacroIndex()),
        "Fishing channel remaining: " .. remaining,
        "Soft interact: " .. (ReadCVar("softTargetInteract") or "unknown"),
        "Interact arc: " .. (ReadCVar("SoftTargetInteractArc") or "unknown"),
        "Interact range: " .. (ReadCVar("SoftTargetInteractRange") or "unknown"),
        string.format("Range check delay: %.2fs", self.currentRangeDelay or self.db.rangeDelay),
        string.format((self.db.cameraAssist and "Recast delay: %.1fs" or "Good cast recast delay: %.1fs"), self.currentRecastDelay or self.db.recastDelay),
        string.format("Hook delay: %.1fs", self.currentHookDelay or self.db.hookDelay),
        string.format("Rapid press lock: %.2fs; %.2fs remaining", self.db.pressLock, self:CastInputLockRemaining()),
        self:RangeSoundTitle() .. ": " .. (self:RangeSoundChoice(self.db.rangeSound) or self.rangeSoundChoices[1]).label,
        "Recast reminder sound: " .. (self:RangeSoundChoice(self.db.recastReminderSound) or self.rangeSoundChoices[1]).label,
        "Catch confirmed sound: " .. (self:RangeSoundChoice(self.db.catchConfirmedSound) or self.rangeSoundChoices[1]).label,
        "Fish escaped sound: " .. (self:RangeSoundChoice(self.db.fishEscapedSound) or self.rangeSoundChoices[1]).label,
        "Alert sounds: " .. (self.db.enableAlertSounds and "on" or "off"),
        string.format("Recast reminder delay: %ds; repeat: %s", self.db.recastReminderDelay, self.db.recastReminderLoop and "on" or "off"),
        self:RangeSoundTitle() .. " repeat: " .. (self.db.rangeSoundLoop and "on" or "off"),
        string.format("Repeat interval: %g s", self.db.soundRepeatInterval),
        "Soft target snapshot (not readiness): " .. bobberState,
        "Soft interact target: " .. bobberTarget,
        "Camera assist: " .. (self.db.cameraAssist and (self.cameraAssistNeeded and
            ((self.cameraAssistBobber or (self.cameraCast and self.cameraCast.bobberLocated)) and "bobber found"
                or (self.cameraState == "RESTORE_HOME" and "returning view")
                or (self.cameraScanFailed and "scan failed/cancelled")
                or (self.cameraState == "PAUSED" and "paused")
                or (self.cameraSweepPreparation and "preparing view")
                or (self.cameraScanStarted and "scanning") or "waiting for cursor") or "waiting") or "off"),
        string.format("Scan speed: %.1fx; this cast: %.1fx", self.db.cameraScanSpeed, self.cameraHome and self.cameraHome.speed or self.db.cameraScanSpeed),
        "Rounded turns: " .. (self.db.cameraRoundedTurns and "on" or "off"),
        "Racetrack turns: " .. (self.db.cameraRacetrackTurns and "on" or "off"),
        "Scan profile: " .. self:CameraScanProfileName(),
        "Saved fishing view: " .. (self.db.cameraSavedView and "On" or "Off") .. "; " .. (self.cameraSavedViewStatus or "not prepared this login"),
        string.format("Sweep: zoom %.1f (achieved %s); home tilt %+.1f degrees; %.2f degree spacing; %d degrees each side; %d rows down; start %.2f degrees down",
            self.db.cameraSweepZoom, self.cameraSweepAchievedZoom and string.format("%.2f", self.cameraSweepAchievedZoom) or "not prepared",
            self.db.cameraSweepTilt, self.db.cameraSweepSpacing, self.db.cameraSweepReach, self.db.cameraSweepRows, self.db.cameraSweepStart),
        "Camera scan: step " .. tostring(self.cameraScanCompletedSteps or 0) .. "; other object samples " .. tostring(self.cameraScanObjectSamples or 0) .. "; last object " .. tostring(self.cameraScanLastObject or "none"),
        "Lure: " .. tostring(self.db.lure or "none") .. (self.db.lureManual and " (manual)" or " (automatic)"),
        "Lure bag slot: " .. (lureEntry and (lureEntry.bag .. "/" .. lureEntry.slot) or "none"),
        "Lure click: " .. (lureButton and ("type " .. tostring(lureButton:GetAttribute("type1")) .. "; macro " .. tostring(lureMacro) .. "; on key down " .. tostring(lureButton:GetAttribute("useOnKeyDown"))) or "button unavailable"),
        "Lure macro body: " .. (lureBody and lureBody:gsub("\n", " | ") or "none"),
        "Lure button error: " .. (self.lureMacroError or "none"),
        "Lure last click: " .. (self.lastLureClick and string.format("%.1fs ago; targeting %s", GetTime() - self.lastLureClick, tostring(self.lastLureTargeting)) or "none this login"),
        "Equipped main hand: " .. tostring(GetInventoryItemID and GetInventoryItemID("player", 16) or "none"),
        "",
        "Recent transitions (oldest first):",
    }
    if #self.recentTransitions == 0 then
        lines[#lines + 1] = "No fishing transitions this login."
    else
        for _, entry in ipairs(self.recentTransitions) do
            lines[#lines + 1] = string.format("%.1fs ago: %s", GetTime() - entry.at, entry.message)
        end
    end
    self:AppendFishingTraceSnapshot(lines, traceSnapshot)
    local report = table.concat(lines, "\n")
    if self.CameraDeveloperReport then report = report .. "\n\n" .. self:CameraDeveloperReport(false, true) end
    if self.ShowTraceWindow then self:ShowTraceWindow(report) else self:Print(report) end
end

-- Profession Fishing may not cast from a SecureActionButton spell attribute on
-- modern clients. Both the visible button and its key binding use a real /cast
-- macro so the cast input can be observed before the next press.
function FF:CastMacroIndex()
    if not GetMacroIndexByName or not GetMacroBody then return nil end
    local index = GetMacroIndexByName(MACRO_NAME)
    if not index or index <= 0 then return nil end
    local body = (GetMacroBody(index) or ""):match("^%s*(.-)%s*$")
    return body == "/cast " .. self:FishingName() and index or nil
end

function FF:EnsureCastMacro()
    if not GetMacroIndexByName or not GetMacroBody or not CreateMacro then return nil end
    local validIndex = self:CastMacroIndex()
    if validIndex then return validIndex end
    local index = GetMacroIndexByName(MACRO_NAME)
    if index and index > 0 then
        self:Print(FF:LocalizedText("runtime.macro-conflict", MACRO_NAME))
        return nil
    end
    if not SafeOutOfCombat() then return nil end
    local ok, result = pcall(CreateMacro, MACRO_NAME, 134400, "/cast " .. self:FishingName(), true)
    if ok and result then return self:CastMacroIndex() end
    self:Print(FF:LocalizedText("runtime.macro-slots-full"))
    return nil
end

-- Creating or deleting any character macro can renumber the secure button's
-- numeric macro slot. Never keep a slot unless it still contains our cast.
function FF:RefreshCastMacro()
    if not SafeOutOfCombat() then return end
    local index = self:CastMacroIndex()
    if index == self.castMacroIndex and (not self:GetFishingCastButton() or self:GetFishingCastButton():GetAttribute("macro") == index) then return end
    self.castMacroIndex = index
    if self.castButton then self:SyncCastAction() end
    if self.db then self:ApplyBindings() end
end

function FF:ShowStatus()
    local key = self.db.key
    local channel, _, ends = IsFishingChannel()
    local remaining = channel and ends and string.format("%.1fs", math.max(0, ends - GetTime())) or "none"
    self:Print("Key " .. (key or "none") .. "; bar " .. (self.bar and self.bar:IsShown() and "open" or "closed") .. "; addon mode " .. self:BindingMode() .. "; actual binding " .. BindingAction(key) .. "; fishing channel " .. remaining .. ".")
    self:Print("Soft interact " .. (ReadCVar("softTargetInteract") or "unknown") .. "; arc " .. (ReadCVar("SoftTargetInteractArc") or "unknown") .. "; range " .. (ReadCVar("SoftTargetInteractRange") or "unknown") .. ".")
    self:Print(string.format("Rapid press lock %.2fs; range check %.2fs; good cast recast %.1fs; hook ready %.1fs after cast start.", self.db.pressLock, self.currentRangeDelay or self.db.rangeDelay, self.currentRecastDelay or self.db.recastDelay, self.currentHookDelay or self.db.hookDelay))
    self:Print(self:RangeSoundTitle() .. ": " .. (self:RangeSoundChoice(self.db.rangeSound) or self.rangeSoundChoices[1]).label .. ".")
    self:Print("Camera assist: " .. (self.db.cameraAssist and (self.cameraAssistNeeded and ((self.cameraAssistBobber or (self.cameraCast and self.cameraCast.bobberLocated)) and "bobber found" or (self.cameraScanFailed and "scan failed" or "scanning")) or "waiting") or "off") .. ".")
    local bobberState, bobberTarget = self:BobberInteractState()
    self:Print("Bobber interact state " .. bobberState .. "; soft interact target " .. bobberTarget .. ".")
end

local function SameCVarValue(a, b)
    if a == nil or b == nil then return false end
    if tostring(a) == tostring(b) then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and y ~= nil and math.abs(x - y) < 0.000001
end

local function ChangeCVar(name, value, snapshot)
    if not SetCVar then return end
    local old = ReadCVar(name)
    if not old or old == "" or SameCVarValue(old, value) then return end
    local ok = pcall(SetCVar, name, tostring(value))
    local applied = ok and ReadCVar(name)
    if SameCVarValue(applied, value) then
        local entry = snapshot[name]
        snapshot[name] = { old = type(entry) == "table" and entry.old or old, applied = applied }
    end
end

function FF:RestoreCVars(field)
    local snapshot = self.db and self.db[field]
    if type(snapshot) ~= "table" then return end
    -- Interaction CVars can be protected in combat. pcall cannot suppress
    -- ADDON_ACTION_BLOCKED; retain the owned snapshot for regeneration/login.
    if field == "interactRestore" and not SafeOutOfCombat() then return end
    local restoringSound = field == "soundRestore"
    if restoringSound then self.changingSplashCVars = true end
    if SetCVar then
        for name, entry in pairs(snapshot) do
            if type(entry) == "table" and entry.old then
                local current = ReadCVar(name)
                if field == "bobberIconRestore" and (current == nil or current == "") then
                    -- Keep the old value until the client exposes this CVar.
                elseif SameCVarValue(current, entry.applied) then
                    local ok = pcall(SetCVar, name, entry.old)
                    if ok and SameCVarValue(ReadCVar(name), entry.old) then snapshot[name] = nil end
                else
                    -- Keep later changes made by the player or another addon.
                    snapshot[name] = nil
                end
            else snapshot[name] = nil end
        end
    end
    if restoringSound then self.changingSplashCVars = nil end
    if not next(snapshot) then self.db[field] = nil end
end

function FF:SyncBackgroundFPS()
    if not self.db then return end
    if not self.bar or not self.bar:IsShown() then
        self:RestoreCVars("backgroundFPSRestore")
        return
    end
    if type(self.db.backgroundFPSRestore) == "table" then return end
    local enabled = ReadCVar("useMaxFPSBk")
    if enabled ~= nil and enabled ~= "" and tonumber(enabled) ~= 1 then return end
    local limit = tonumber(ReadCVar("maxFPSBk"))
    if not limit or limit <= 0 or limit >= 60 then return end
    local snapshot = {}
    ChangeCVar("maxFPSBk", 60, snapshot)
    if next(snapshot) then self.db.backgroundFPSRestore = snapshot end
end

function FF:SyncAutoLoot()
    if not self.db then return end
    if not self.bar or not self.bar:IsShown() then
        self:RestoreCVars("autoLootRestore")
        return
    end
    if type(self.db.autoLootRestore) == "table" then return end
    if tonumber(ReadCVar("autoLootDefault")) ~= 0 then return end
    local snapshot = {}
    ChangeCVar("autoLootDefault", 1, snapshot)
    if next(snapshot) then self.db.autoLootRestore = snapshot end
end

-- The icon is a bar-owned native interaction aid. Keep its original value in
-- the same recoverable CVar format as the other temporary fishing settings.
function FF:SyncBobberInteractIcon()
    if not self.db then return end
    if not self.bar or not self.bar:IsShown() then
        self:RestoreCVars("bobberIconRestore")
        return
    end
    local name = "SoftTargetIconGameObject"
    local current = ReadCVar(name)
    if current == nil or current == "" then return end
    local snapshot = self.db.bobberIconRestore
    local entry = type(snapshot) == "table" and snapshot[name]
    if type(entry) == "table" then
        if SameCVarValue(current, entry.applied) then return end
        -- A changed value is now the player's preference, not our old one.
        snapshot[name] = nil
        self.db.bobberIconRestore = nil
    end
    if SameCVarValue(current, 1) or not SetCVar then return end
    snapshot = { [name] = { old = current, applied = "1" } }
    self.db.bobberIconRestore = snapshot -- arm before the native callback
    pcall(SetCVar, name, "1")
    if self.db.bobberIconRestore ~= snapshot then return end
    local applied = ReadCVar(name)
    if applied ~= nil and applied ~= "" and not SameCVarValue(applied, 1) then
        self.db.bobberIconRestore = nil
    end
end

function FF:SyncLongRangeCameraDistance()
    if not self.db then return end
    if self.db.cameraProfile ~= "standard" then
        self:RestoreCVars("cameraDistanceRestore")
        return
    end
    local snapshot = self.db.cameraDistanceRestore
    local entry = type(snapshot) == "table" and snapshot.cameraDistanceMaxZoomFactor
    if type(entry) == "table" and SameCVarValue(ReadCVar("cameraDistanceMaxZoomFactor"), entry.applied) then return end
    -- A later change is the new preference to restore after this scan path.
    self.db.cameraDistanceRestore = nil
    snapshot = {}
    ChangeCVar("cameraDistanceMaxZoomFactor", 2, snapshot)
    if next(snapshot) then self.db.cameraDistanceRestore = snapshot end
end

-- One calibrated projection for all fishing paths; never enforce it per frame.
FF.fishingFOVTarget = 90
local function FOVNumber(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) ~= "number" and type(value) ~= "string" then return nil end
    local number = tonumber(value)
    if number and number == number and math.abs(number) ~= math.huge then return number end
end
local function FOVEntry(self)
    local snapshot = self.db and self.db.cameraFOVRestore
    if issecretvalue and issecretvalue(snapshot) then return end
    if type(snapshot) ~= "table" then return end
    local entry = rawget(snapshot, "cameraFov")
    if issecretvalue and issecretvalue(entry) then return end
    if type(entry) == "table" then return FOVNumber(rawget(entry, "old")), FOVNumber(rawget(entry, "applied")) end
end
local function WantsFishingFOV(self)
    return self.db and self.db.cameraAssist and self.bar and self.bar:IsShown()
end
local function NPCCameraActive()
    if issecretvalue and (issecretvalue(C_PlayerInteractionManager) or issecretvalue(Enum)) then return false end
    local api = type(C_PlayerInteractionManager) == "table" and rawget(C_PlayerInteractionManager, "IsInteractingWithNpcOfType")
    local kinds = type(Enum) == "table" and rawget(Enum, "PlayerInteractionType")
    if issecretvalue and issecretvalue(kinds) then return false end
    if type(api) ~= "function" or type(kinds) ~= "table" then return false end
    for _, name in ipairs({ "Gossip", "QuestGiver" }) do
        local kind = FOVNumber(rawget(kinds, name))
        if kind then
            local ok, active = pcall(api, kind)
            if ok and not (issecretvalue and issecretvalue(active)) and active == true then return true end
        end
    end
    return false
end
function FF:RelinquishFishingFOV()
    local old, applied = FOVEntry(self)
    if not old or not applied then return end
    local actual = self:ReadFishingFOV()
    if old and applied and actual and math.abs(actual - applied) > 0.0001 then
        self.db.cameraFOVRestore = nil
        self.cameraFOVState = { original = old, requested = self.fishingFOVTarget, achieved = actual, status = "external change; relinquished" }
    end
end
function FF:ReleaseFishingFOV(force)
    if not self.db or self.cameraOwnFOV then return end
    if not force and self.cameraCenteredReturn and self.cameraEndSessionAfterRestore then
        self.fishingFOVReleasePending = true
        return
    end
    self.fishingFOVReleasePending = nil
    local old, applied = FOVEntry(self)
    if not old or not applied then self.db.cameraFOVRestore = nil; return end
    local actual = self:ReadFishingFOV()
    if not actual then return end -- Preserve recovery metadata until readable.
    if math.abs(actual - applied) > 0.0001 then self:RelinquishFishingFOV(); return end
    self.cameraOwnFOV = true
    -- World/combat cancellation must not leave old motion under restored FOV.
    if self.cameraHome and self.cameraHome.valid then self:InvalidateScanHome("Fishing FOV released") end
    self:WriteFishingFOV(old)
    actual = self:ReadFishingFOV()
    self.cameraOwnFOV = nil
    if actual and math.abs(actual - old) < 0.0001 then
        self.db.cameraFOVRestore = nil
        self.cameraFOVState = { original = old, requested = self.fishingFOVTarget, achieved = actual, status = "restored" }
    elseif actual and math.abs(actual - applied) > 0.0001 then self:RelinquishFishingFOV() end
end
function FF:SyncFishingFOV()
    if not self.db or self.cameraOwnFOV then return false end
    if not WantsFishingFOV(self) then self:ReleaseFishingFOV(); return true end
    if not self.ReadFishingFOV then return true end
    self.fishingFOVReleasePending = nil
    if NPCCameraActive() then
        self.cameraFOVState = { requested = self.fishingFOVTarget, status = "NPC interaction active; deferred" }
        return false
    end
    local actual = self:ReadFishingFOV()
    local old, applied = FOVEntry(self)
    if not actual then
        self.cameraFOVState = { original = old, requested = self.fishingFOVTarget, status = "unavailable; unverified" }
        return true -- Optional API absence must not disable otherwise working fishing.
    end
    if old and applied then self:RelinquishFishingFOV() end
    if math.abs(actual - self.fishingFOVTarget) < 0.0001 then
        self.cameraFOVState = { original = old or actual, requested = self.fishingFOVTarget, achieved = actual,
            status = old and applied and "owned" or "already calibrated" }
        return true
    end
    if InCombatLockdown and InCombatLockdown() then return false end
    -- Arm before the native call so a reentrant bar close can restore safely.
    local snapshot = { cameraFov = { old = tostring(actual), applied = tostring(self.fishingFOVTarget) } }
    self.db.cameraFOVRestore = snapshot
    self.cameraOwnFOV = true
    self:WriteFishingFOV(self.fishingFOVTarget)
    self.cameraOwnFOV = nil
    local achieved = self:ReadFishingFOV()
    if self.db.cameraFOVRestore ~= snapshot or not WantsFishingFOV(self) then self:ReleaseFishingFOV(true); return false end
    self.cameraFOVState = { original = actual, requested = self.fishingFOVTarget, achieved = achieved, status = "write unverified" }
    if achieved and math.abs(achieved - self.fishingFOVTarget) < 0.0001 then
        self.cameraFOVState.status = "owned"
        self:CheckCameraEnvironment("fishing FOV prepared")
        return true
    end
    self:ReleaseFishingFOV(true)
    return false
end

-- Take ordinary fishing items as soon as loot is ready. Leave uncertain loot
-- and full bags to WoW's normal loot handling. No frame hooks or polling.
function FF:FastLootFishingItems(autoLoot)
    if autoLoot ~= true or not (self.db and self.db.fastAutoLoot) or
        not (self.bar and self.bar:IsShown()) or not
        (IsFishingLoot and GetNumLootItems and GetLootSlotType and GetLootSlotLink and GetLootSlotInfo and LootSlot) then return end
    local addonLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if addonLoaded and addonLoaded("SpeedyAutoLoot") then return end
    local ok, fishing = pcall(IsFishingLoot)
    if not ok or not fishing then return end

    local freeSlots = 0
    local freeInBag = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if not freeInBag then return end
    for bag = 0, 4 do
        local valid, count, family = pcall(freeInBag, bag)
        if valid and (family == 0 or family == nil) then freeSlots = freeSlots + (tonumber(count) or 0) end
    end
    if freeSlots < 1 then return end

    for slot = 1, GetNumLootItems() do
        if freeSlots < 1 then break end
        local link = GetLootSlotType(slot) == 1 and GetLootSlotLink(slot)
        if link then
            local _, _, quantity, _, _, locked, questItem = GetLootSlotInfo(slot)
            if not locked and not questItem then
                local maxStack = C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(link)
                if not maxStack and GetItemInfo then
                    local _, _, _, _, _, _, _, stack = GetItemInfo(link)
                    maxStack = stack
                end
                local amount = math.max(1, tonumber(quantity) or 1)
                local needed = maxStack and maxStack > 0 and math.ceil(amount / maxStack) or amount
                if needed <= freeSlots then
                    local taken = pcall(LootSlot, slot)
                    if not taken then break end
                    -- Count full stacks conservatively; existing partial stacks
                    -- can only make more room available.
                    freeSlots = freeSlots - needed
                end
            end
        end
    end
end

function FF:AutoLootCVarChanged(name)
    if type(name) ~= "string" or name:lower() ~= "autolootdefault" then return end
    local snapshot = self.db and self.db.autoLootRestore
    if type(snapshot) ~= "table" then return end
    local entry = snapshot.autoLootDefault
    if type(entry) == "table" and not SameCVarValue(ReadCVar("autoLootDefault"), entry.applied) then
        -- A later change to the player's setting ends our ownership of it.
        self.db.autoLootRestore = nil
    end
end

function FF:PrepareInteract()
    if self.db.interactAssist == false or not SafeOutOfCombat() then return end
    -- A newer channel may inherit a restore deferred by combat. Keep its
    -- original baseline only while the corresponding applied value is ours.
    local snapshot = type(self.db.interactRestore) == "table" and self.db.interactRestore or {}
    for name, entry in pairs(snapshot) do
        if type(entry) ~= "table" or not SameCVarValue(ReadCVar(name), entry.applied) then
            snapshot[name] = nil
        end
    end
    local flags = Enum and Enum.SoftTargetEnableFlags
    ChangeCVar("softTargetInteract", flags and flags.Any or 3, snapshot)
    local arc = tonumber(ReadCVar("SoftTargetInteractArc"))
    if arc and arc < 2 then ChangeCVar("SoftTargetInteractArc", 2, snapshot) end
    local range = tonumber(ReadCVar("SoftTargetInteractRange"))
    if range and range < 30 then ChangeCVar("SoftTargetInteractRange", 30, snapshot) end
    self.db.interactRestore = next(snapshot) and snapshot or nil
end

-- Own one temporary audio session for the open fishing bar, not each cast.
-- Saved Focus preferences are separate from the temporary normal-mix snapshot.
local function FocusMixVolume(self, name, fallback)
    local profile = self.db and self.db.soundFocusVolumes
    local value = type(profile) == "table" and tonumber(profile[name])
    if not value or value ~= value or value == math.huge or value == -math.huge then return fallback or 0 end
    return math.max(0, math.min(1, value))
end

local function RememberFocusVolume(self, name, value)
    if not self.soundFocusSession or not self.db then return end
    local profile = self.db.soundFocusVolumes
    if type(profile) ~= "table" then profile = {}; self.db.soundFocusVolumes = profile end
    profile[name] = value
end

function FF:FocusSplashSound()
    local wanted = self.db and self.db.soundFocus and self.bar and self.bar:IsShown()
        and not self.soundAlertsSuspended
    if not wanted then
        self.soundFocusSession = nil
        self:RestoreCVars("soundRestore")
        return
    end
    if self.soundFocusSession then return end
    self.soundFocusSession = true
    local snapshot = type(self.db.soundRestore) == "table" and self.db.soundRestore or {}
    self.db.soundRestore = snapshot
    self.changingSplashCVars = true
    ChangeCVar("Sound_EnableAllSound", 1, snapshot)
    -- Older clients may expose this alias. Unknown CVars are skipped.
    ChangeCVar("Sound_EnableSound", 1, snapshot)
    ChangeCVar("Sound_EnableSFX", 1, snapshot)
    -- Missing Master preference leaves the current level unchanged. Explicit
    -- fishing choices share the same owned normal-mix snapshot as Music/Ambience.
    local sfx = tonumber(ReadCVar("Sound_SFXVolume"))
    if sfx and sfx < 0.9 then ChangeCVar("Sound_SFXVolume", 0.9, snapshot) end
    for _, name in ipairs({ "Sound_MasterVolume", "Sound_MusicVolume", "Sound_AmbienceVolume", "Sound_DialogVolume" }) do
        local volume = tonumber(ReadCVar(name))
        local target = name == "Sound_DialogVolume" and 0 or FocusMixVolume(self, name, name == "Sound_MasterVolume" and volume or nil)
        if volume then ChangeCVar(name, target, snapshot) end
    end
    self.changingSplashCVars = nil
    if not next(snapshot) then self.db.soundRestore = nil end
end

-- The three Settings sliders edit the active Focus mix, not the player's normal
-- game mix. Keep verified choices for later sessions; record a zero baseline too.
function FF:SetFocusSplashVolume(name, value)
    if name ~= "Sound_MasterVolume" and name ~= "Sound_MusicVolume" and name ~= "Sound_AmbienceVolume" then return end
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return end
    value = math.max(0, math.min(1, value))
    if not SetCVar then return end
    local snapshot = self.soundFocusSession and self.db and self.db.soundRestore
    local old = ReadCVar(name)
    if not old or old == "" then return end
    if SameCVarValue(old, value) then
        RememberFocusVolume(self, name, value)
        return
    end
    local entry = type(snapshot) == "table" and snapshot[name]
    if self.soundFocusSession and type(entry) ~= "table" then
        snapshot = type(snapshot) == "table" and snapshot or {}
        self.db.soundRestore = snapshot
        entry = { old = old, applied = old }
        snapshot[name] = entry
    end
    self.changingSplashCVars = true
    local ok = pcall(SetCVar, name, tostring(value))
    self.changingSplashCVars = nil
    local applied = ok and ReadCVar(name)
    if SameCVarValue(applied, value) then RememberFocusVolume(self, name, value) end
    if type(entry) == "table" and SameCVarValue(applied, value) then
        entry.applied = applied
    elseif type(entry) == "table" and SameCVarValue(entry.old, entry.applied) then
        -- A rejected first slider write created no temporary change to own.
        snapshot[name] = nil
        if not next(snapshot) then self.db.soundRestore = nil end
    end
end

function FF:SplashSoundCVarChanged(name)
    if self.changingSplashCVars or not self.soundFocusSession or type(name) ~= "string" then return end
    local snapshot = self.db and self.db.soundRestore
    if type(snapshot) ~= "table" then return end
    for key, entry in pairs(snapshot) do
        if key:lower() == name:lower() and not SameCVarValue(ReadCVar(key), entry.applied) then
            snapshot[key] = nil
            break
        end
    end
    if not next(snapshot) then self.db.soundRestore = nil end
end

-- This is the same CVar as Blizzard's Audio > Sound in Background checkbox.
-- Treat it as the user's game setting, rather than a temporary fishing override.
function FF:BackgroundSoundEnabled()
    local value = ReadCVar(BACKGROUND_SOUND_CVAR)
    if value == nil or value == "" then return nil end
    return value == "1" or value == "true"
end

function FF:SetBackgroundSoundEnabled(enabled)
    if not SetCVar or self:BackgroundSoundEnabled() == nil then return false end
    local ok = pcall(SetCVar, BACKGROUND_SOUND_CVAR, enabled and "1" or "0")
    if not ok or self:BackgroundSoundEnabled() ~= enabled then return false end
    local snapshot = self.db and self.db.soundRestore
    if type(snapshot) == "table" then
        snapshot[BACKGROUND_SOUND_CVAR] = nil
        if not next(snapshot) then self.db.soundRestore = nil end
    end
    return true
end

function FF:CastInputLockRemaining()
    return math.max(0, (self.castInputLockUntil or 0) - GetTime())
end

function FF:CastInputLocked()
    -- A fresh attempt must be protected while the old channel may still
    -- report a too-far bobber. A confirmed too-far result from the new cast
    -- can bypass this short lock once that channel starts.
    return (self.db.pressLock or 0) > 0 and self:CastInputLockRemaining() > 0
        and (self.castAttemptPending or not (self.db.cameraAssist and self.recastReady))
end

function FF:BeginCastInputLock(channelStarted)
    local duration = self.db.pressLock or 0
    if duration <= 0 then return end
    self.castAttemptPending = not channelStarted
    self.castInputLockUntil = GetTime() + duration
    self.castInputLockToken = (self.castInputLockToken or 0) + 1
    local token = self.castInputLockToken
    self:ApplyBindings()
    if self.SyncCastAction then self:SyncCastAction() end
    self:TraceTransition(string.format("cast button pressed; rapid press lock %.2fs", duration))
    if C_Timer and C_Timer.After then
        C_Timer.After(duration + 0.02, function()
            if self.castInputLockToken ~= token then return end
            self.castAttemptPending = nil
            self:ApplyBindings()
            if self.SyncCastAction then self:SyncCastAction() end
            self:RefreshUI()
        end)
    end
end

function FF:SetAutoEquipGear(enabled)
    if not SafeOutOfCombat() then
        self:Print(FF:LocalizedText("runtime.gear-combat"))
        return false
    end
    self.db.autoEquipGear = enabled == true
    self:RefreshUI()
    return true
end

function FF:SetAutoEquipLures(enabled)
    if not SafeOutOfCombat() then
        self:Print(FF:LocalizedText("runtime.lure-combat"))
        return false
    end
    self.db.autoEquipLures = enabled == true
    self:RefreshUI()
    return true
end

-- Target inspection is confined to an armed player cast click. A matching soft
-- interact identity proves this NPC offers interaction; distance and disposition
-- guards keep players, enemies, pets, distant and unreadable targets untouched.
local function CastTargetFact(name, ...)
    local callback = rawget(_G, name)
    if (issecretvalue and issecretvalue(callback)) or type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end

function FF:CloseFishingNPCInteraction(button)
    if not self.castClickArmed or not self.castClickInProgress or not SafeOutOfCombat()
        or not self.bar or not self.bar:IsShown() or not button or button ~= self:GetFishingCastButton()
        or button:GetAttribute("type") ~= "macro" or not self.castMacroIndex
        or button:GetAttribute("macro") ~= self.castMacroIndex then return end
    if issecretvalue and (issecretvalue(C_PlayerInteractionManager) or issecretvalue(Enum)) then return end
    local api = type(C_PlayerInteractionManager) == "table" and C_PlayerInteractionManager
    local kinds = type(Enum) == "table" and rawget(Enum, "PlayerInteractionType")
    if not api or (issecretvalue and issecretvalue(kinds)) or type(kinds) ~= "table" then return end
    local query, close = rawget(api, "IsInteractingWithNpcOfType"), rawget(api, "ClearInteraction")
    if issecretvalue and (issecretvalue(query) or issecretvalue(close)) then return end
    if type(query) ~= "function" or type(close) ~= "function" then return end
    -- End the native session, not just its frame. Replacement dialogue UIs also
    -- receive the native close event. Never close unrelated panels/interactions.
    for _, name in ipairs({ "Merchant", "Gossip" }) do
        local kind = FOVNumber(rawget(kinds, name))
        if kind then
            local ok, active = pcall(query, kind)
            if ok and not (issecretvalue and issecretvalue(active)) and active == true then
                local guid = CastTargetFact("UnitGUID", "npc")
                local selected = CastTargetFact("UnitGUID", "target")
                if not SafeOutOfCombat() or not self.castClickArmed or not self.castClickInProgress
                    or not self.bar:IsShown() then return end
                -- Only one close request; callbacks may synchronously replace
                -- the interaction or refresh bindings and secure attributes.
                local closed = pcall(close, kind)
                if closed then
                    local checked, stillActive = pcall(query, kind)
                    if checked and not (issecretvalue and issecretvalue(stillActive)) and stillActive == false then
                        self:TraceTransition("cast click: closed native " .. name .. " interaction")
                        return guid, selected, true
                    end
                end
                return nil, selected, true
            end
        end
    end
end

function FF:PrepareBlockingFishingTargetClear(button, closedNPCGUID)
    if not self.castClickArmed or not self.castClickInProgress or not SafeOutOfCombat()
        or not self.bar or not self.bar:IsShown() or button ~= self:GetFishingCastButton()
        or button:GetAttribute("type") ~= "macro"
        or not self.castMacroIndex or button:GetAttribute("macro") ~= self.castMacroIndex then return false end
    local guid = CastTargetFact("UnitGUID", "target")
    if type(guid) ~= "string" or not (guid:match("^Creature%-") or guid:match("^Vehicle%-")) then return false end
    if CastTargetFact("UnitPlayerControlled", "target") ~= false
        or CastTargetFact("UnitCanAttack", "player", "target") ~= false
        or CastTargetFact("UnitIsDeadOrGhost", "target") ~= false
        or CastTargetFact("CheckInteractDistance", "target", 4) ~= true then return false end
    -- Closing a verified NPC session can remove its soft-interact identity.
    -- Retain only that click's native npc GUID, never a name or stale frame.
    if CastTargetFact("UnitGUID", "softinteract") ~= guid and closedNPCGUID ~= guid then return false end
    if not SafeOutOfCombat() or not self.castClickArmed or not self.bar:IsShown()
        or CastTargetFact("UnitGUID", "target") ~= guid then return false end
    -- ClearTarget is protected even from ordinary PreClick Lua. Only the native
    -- secure macro action may execute it, on this player's already-armed click.
    -- Numeric macro takes precedence over macrotext, so clear it for this click.
    -- Do not edit the saved cast macro or call any protected targeting API here.
    button:SetAttribute("macrotext", "/cleartarget [nocombat]\n/cast " .. self:FishingName())
    button:SetAttribute("macro", nil)
    self:TraceTransition("cast click: prepared secure blocking NPC target clear")
    return true
end

function FF:OnCastButtonPreClick(button)
    if self.db.autoEquipLures and self.ValidateSelectedLureSlot and self:ValidateSelectedLureSlot() then
        self:RefreshSmartButtons()
    end
    -- Last chance to catch a slot change before the secure macro action runs.
    if self:CastMacroIndex() ~= self.castMacroIndex or button:GetAttribute("macro") ~= self.castMacroIndex then
        self:RefreshCastMacro()
    end
    self:SyncCastAction()
    self.castClickAction = self.castAction
    if self.castClickAction == "gear" and not (InCombatLockdown and InCombatLockdown()) then
        self:EquipConfiguredFishingGear(true)
        -- Equipping may refresh the UI before this secure click resolves.
        button:SetAttribute("type", nil)
    end
    self.castClickInProgress = true
    self.castClickArmed = self.castClickAction == "cast" and button:GetAttribute("type") == "macro" and not self:CastInputLocked()
    self.castClickChannelSerial = self.channelStartSerial or 0
    if self.castClickArmed then
        local closedNPCGUID, selectedGUID, closeAttempted = self:CloseFishingNPCInteraction(button)
        -- Native close callbacks may change combat, bar/action or macro state.
        if closeAttempted then
            self:SyncCastAction()
            self.castClickAction = self.castAction
            self.castClickArmed = SafeOutOfCombat() and self.bar and self.bar:IsShown()
                and self.castClickAction == "cast" and button:GetAttribute("type") == "macro" and not self:CastInputLocked()
        end
        if self.castClickArmed then
            if not closeAttempted or CastTargetFact("UnitGUID", "target") == selectedGUID then
                self:PrepareBlockingFishingTargetClear(button, closedNPCGUID)
            end
        elseif closeAttempted and SafeOutOfCombat() then
            button:SetAttribute("type", nil)
        end
    end
end

function FF:OnCastButtonPostClick()
    self.castClickInProgress = nil
    if self:GetFishingCastButton() and self:GetFishingCastButton():GetAttribute("macrotext") then self:SyncCastAction() end
    if self.castClickAction == "lure" then
        self.lureApplyPendingAt = GetTime()
        if C_Timer and C_Timer.After then
            local attempt = self.lureApplyPendingAt
            C_Timer.After(1, function()
                if self.lureApplyPendingAt == attempt and not (UnitCastingInfo and UnitCastingInfo("player")) then
                    self.lureApplyPendingAt = nil
                end
                self:RefreshUI()
            end)
        end
        self:RefreshUI()
    elseif self.castClickAction == "gear" then
        self:RefreshUI()
    end
    self.castClickAction = nil
    if not self.castClickArmed then return end
    self.castClickArmed = nil
    self.lastCastButtonPressAt = GetTime()
    if self.OnFishingRodRequired and self.FishingRodEquippedNow
        and self:FishingRodEquippedNow() == false then
        self.lastFishingCastAttemptAt = GetTime()
        self:OnFishingRodRequired()
        return
    end
    self:OnFishingSoundCastSent()
    self:BeginCastInputLock((self.channelStartSerial or 0) ~= self.castClickChannelSerial)
end

function FF:OnFishingCastSent(spellID)
    if not self.bar or not self.bar:IsShown() or not SafeOutOfCombat() then return end
    if issecretvalue and issecretvalue(spellID) then return end
    local id = tonumber(spellID)
    if id ~= 7620 and id ~= FISHING_SPELL and id ~= FISHING_CAST then
        if not id or SpellName(id) ~= self:FishingName() then return end
    end
    self:OnFishingSoundCastSent()
    -- A click on our secure cast button is recorded at the input point. The
    -- spell event is only a fallback for casts from a separate Fishing button.
    if self.castClickInProgress or GetTime() - (self.lastCastButtonPressAt or -100) < 0.2 then return end
    self:BeginCastInputLock(false)
end

function FF:ConfigureCombatCloseBindings(button)
    if not button or not button.SetFrameRef or not SafeOutOfCombat() then return end
    button:SetFrameRef("castBindings", BIND_OWNER)
    button:SetFrameRef("interactBindings", INTERACT_OWNER)
    if self.doubleClickBindingOwner then button:SetFrameRef("doubleBindings", self.doubleClickBindingOwner) end
end

function FF:ApplyBindings()
    if not SafeOutOfCombat() then return end
    ClearOverrideBindings(BIND_OWNER)
    ClearOverrideBindings(INTERACT_OWNER)
    if not GLOBAL_BIND_OWNER then GLOBAL_BIND_OWNER=CreateFrame("Frame", nil, WorldFrame, "SecureHandlerBaseTemplate") end
    ClearOverrideBindings(GLOBAL_BIND_OWNER)
    local key = self.db and self.db.key
    if key == self.doubleRightClickKey then self:InitializeDoubleClickBinding() end
    if self.doubleClickBindingOwner then
        self:RefreshDoubleClickWatcher()
        ClearOverrideBindings(self.doubleClickBindingOwner)
    end
    self:ConfigureCombatCloseBindings(self.closeButton)
    if self.journalInputFocus or self.settingsKeyboardFocus or self.captureCommitPending or (self.capture and self.capture:IsShown()) then return end
    -- Override the player's normal action-bar binding only while the main
    -- Fishing bar is visible. Closing it restores the original key action.
    if self.ApplyAdditionalFishingBindings then self:ApplyAdditionalFishingBindings(BIND_OWNER, GLOBAL_BIND_OWNER) end
    if not self:IsFishingSessionOpen() then return end
    if not key or key == "" then return end
    if key == "BUTTON4" and self.journalBackBindingApplied then return end
    local bindOwner, interactOwner = BIND_OWNER, INTERACT_OWNER
    if key == self.doubleRightClickKey then
        if not self:DoubleClickArmed() then return end
        key = "BUTTON2"
        bindOwner, interactOwner = self.doubleClickBindingOwner, self.doubleClickBindingOwner
    end
    local cameraRecast = self:CameraRecastReady()
    local nativeChannel = self.active and not self.db.cameraAssist
    if self:CastInputLocked() or (nativeChannel and not self.nativeBobberReady)
        or (self.db.cameraAssist and self.cameraAssistNeeded and (not self.cameraAssistBobber or not self.hookReady) and not cameraRecast)
        or (self.db.cameraAssist and self.active and not self.cameraAssistNeeded and not self.recastReady
            and not self.recastWindow and (not self.hookReady or not self.nativeBobberReady)) then
        SetOverrideBindingClick(bindOwner, true, key, "ForeverFishingGuardButton", "LeftButton")
    elseif self.db.cameraAssist and self.cameraAssistNeeded and self.cameraAssistBobber and self.hookReady then
        SetOverrideBinding(interactOwner, true, key, "INTERACTMOUSEOVER")
    elseif nativeChannel or (self.active and not self.cameraAssistNeeded and not self.recastReady and not self.recastWindow) then
        SetOverrideBinding(interactOwner, true, key, "INTERACTTARGET")
    else
        if self.castMacroIndex or (self.NextFishingAction and self:NextFishingAction() ~= "cast") then
            SetOverrideBindingClick(bindOwner, true, key, "ForeverFishingCastActionButton", "LeftButton")
        elseif SetOverrideBindingSpell then
            SetOverrideBindingSpell(bindOwner, true, key, self:FishingName())
        end
    end

end

function FF:UpdateActionReadiness()
    if not self.active or not SafeOutOfCombat() then return end
    local elapsed = GetTime() - self.bobberCheckStartedAt
    local recastDelay = self.currentRecastDelay or self.db.recastDelay
    local hookDelay = self.currentHookDelay or self.db.hookDelay
    -- Native interaction is gated by verified identity and the input lock,
    -- never by the legacy recast/hook workaround sliders.
    local hookReady = not self.db.cameraAssist or elapsed >= hookDelay
    local recastWindow = self.db.cameraAssist and elapsed >= recastDelay and elapsed < hookDelay or false
    local cameraRecast = self:CameraRecastReady()
    if self.hookReady == hookReady and self.recastWindow == recastWindow and self.cameraRecastAvailable == cameraRecast then return end
    self.hookReady = hookReady
    self.recastWindow = recastWindow
    self.cameraRecastAvailable = cameraRecast
    if not self.recastReady then
        self:ApplyBindings()
        if self.SyncCastAction then self:SyncCastAction() end
        local state = cameraRecast and self.cameraAssistNeeded and not self.cameraAssistBobber and "camera recast available"
            or (recastWindow and (self.db.cameraAssist and "recast window" or "good cast recast window") or (hookReady and "hook ready" or "input lock"))
        self:TraceTransition(state .. "; binding " .. BindingAction(self.db.key))
    end
end

function FF:SetRecastReady(ready, reason)
    ready = ready and self.active and self.db.cameraAssist or false
    self.recastReason = ready and reason or nil
    if self.recastReady == ready or not SafeOutOfCombat() then return end
    self.recastReady = ready
    self:ApplyBindings()
    if self.SyncCastAction then self:SyncCastAction() end
    if ready then self:WarnRangeOnce() end
    local transition = ready and (reason == "blocked" and "another interact target blocks the bobber" or "bobber unavailable to native interaction") or "bobber target returned"
    self:TraceTransition(transition .. "; binding " .. BindingAction(self.db.key))
end

function FF:InitializeFishingMode()
    if self.db.cameraModeDefaultsVersion ~= 2 then
        -- One transition from the old camera-first default. Keep all tuning.
        self.db.cameraAssist = false
        self.db.cameraModeDefaultsVersion = 2
    else self.db.cameraAssist = self.db.cameraAssist == true end
end

function FF:SetCameraAssistEnabled(enabled)
    enabled = enabled == true
    if self.db.cameraAssist == enabled then return end
    self:SaveTimingProfile()
    self.db.cameraAssist = enabled
    self:ActivateTimingProfile()
    self.db.cameraModeDefaultsVersion = 2
    if self.active then
        self.currentRangeDelay, self.currentRecastDelay, self.currentHookDelay = self.db.rangeDelay, self.db.recastDelay, self.db.hookDelay
        self:UpdateActionReadiness()
    end
    if not enabled then self:StopCameraAssist("Camera assist disabled", true) end
    self:SyncFishingFOV()
    if self.settingsPanel then self:RefreshFishingModeSetting() end
    if self.scanDevPanel then self.scanDevPanel:RefreshControls() end
    if self.active and self.UpdateBobberStatus then self:UpdateBobberStatus() end
    self:ApplyBindings()
    if self.SyncCastAction then self:SyncCastAction() end
    self:RefreshUI()
end

function FF:SetKey(key)
    if not SafeOutOfCombat() then self:Print(FF:LocalizedText("binding.choose-outside-combat")); return end
    if self.FishingActionBindingConflict then
        local conflict = self:FishingActionBindingConflict("fishing", key)
        if conflict then self:Print(FF:LocalizedText("binding.unchanged-conflict", conflict)); return end
    end
    if self.ResetDoubleClick then self:ResetDoubleClick(true) end
    self.db.key = key
    self:ApplyBindings()
    self:RefreshUI()
    if self.settingsPanel and self.settingsPanel.RefreshBindingControls then self.settingsPanel:RefreshBindingControls() end
end

function FF:StartChannel(resumed, castGUID, spellID)
    local active, started, ends = IsFishingChannel()
    if not active then return end
    local eventGUID = not (issecretvalue and issecretvalue(castGUID)) and type(castGUID) == "string" and castGUID or nil
    local eventSpell = not (issecretvalue and issecretvalue(spellID)) and type(spellID) == "number" and spellID or nil
    if self.active and (not started or self.castStart == started) then
        -- A resumed channel may receive its native identity after login.
        if not self.fishingChannelGUID then self.fishingChannelGUID = eventGUID end
        if not self.fishingChannelSpell then self.fishingChannelSpell = eventSpell end
        return
    end
    if self.active then self:StopChannel() end
    self.active = true
    self.fishingChannelGUID, self.fishingChannelSpell = eventGUID, eventSpell
    self.channelStartSerial = (self.channelStartSerial or 0) + 1
    self.bobberStatusWarning = nil
    self.nativeBobberReady = false
    self.castAttemptPending = nil
    self.recastReady = false
    self.recastReason = nil
    self.recastWindow = false
    self.cameraRecastAvailable = false
    self.hookReady = false
    self.rangeSoundPlayed = false
    self.castStart = started or GetTime()
    self.bobberCheckStartedAt = GetTime()
    self.bobberMissingSince = nil
    self.bobberBlockedSince = nil
    self.bobberUnknownSince, self.cameraSoftBobberSince = nil, nil
    self.currentRangeDelay = self.db.rangeDelay
    self.currentRecastDelay = self.db.recastDelay
    self.currentHookDelay = self.db.hookDelay
    self.castEnd = ends
    self.lastFishingHookAt = nil
    self.soundCastWaitUntil = nil
    self:CancelPendingCastSound()
    self.lootRecorded = false
    self:CameraCastStarted(resumed)
    if self.HideFishingRodWarning then self:HideFishingRodWarning() end
    self:BeginFishingStatistics(resumed)
    self:PrepareInteract()
    self:FocusSplashSound()
    self:SyncFishingSounds()
    self:ApplyBindings()
    if self.ResumeFishingUIHidingOnCast then self:ResumeFishingUIHidingOnCast(resumed) end
    self:TraceTransition("channel start; binding " .. BindingAction(self.db.key) .. "; interact " .. (ReadCVar("softTargetInteract") or "?") .. "/" .. (ReadCVar("SoftTargetInteractArc") or "?") .. "/" .. (ReadCVar("SoftTargetInteractRange") or "?"))
    self:RefreshUI()
end

function FF:StopChannel(reason, castGUID, spellID)
    -- Only native stop/interruption events carry identity. Explicit bar/world
    -- cleanup still uses the ordinary unconditional lifecycle.
    if self.active and (reason == "UNIT_SPELLCAST_CHANNEL_STOP" or reason == "UNIT_SPELLCAST_INTERRUPTED") then
        local eventGUID = not (issecretvalue and issecretvalue(castGUID)) and type(castGUID) == "string" and castGUID or nil
        local eventSpell = not (issecretvalue and issecretvalue(spellID)) and type(spellID) == "number" and spellID or nil
        if eventGUID and self.fishingChannelGUID and eventGUID ~= self.fishingChannelGUID then
            self:TraceTransition("ignored stale fishing channel stop")
            return
        end
        if eventSpell and eventSpell ~= self.fishingChannelSpell and eventSpell ~= 7620
            and eventSpell ~= FISHING_SPELL and eventSpell ~= FISHING_CAST
            and SpellName(eventSpell) ~= self:FishingName() then return end
    end
    self.bobberStatusWarning = nil
    self:StopFishingSound("range", true)
    if not self.active then return end
    self:CameraChannelEnded(reason)
    self:EndFishingStatistics(reason)
    local remaining = self.castEnd and string.format("%.1fs", self.castEnd - GetTime()) or "unknown"
    self.lastFishingHookAt = self.castEnd and self.castEnd - GetTime() > 1 and GetTime() or nil
    self.active = false
    self.nativeBobberReady = false
    self.fishingChannelGUID, self.fishingChannelSpell = nil, nil
    self.recastReady = false
    self.recastReason = nil
    self.recastWindow = false
    self.cameraRecastAvailable = false
    self.hookReady = false
    self.rangeSoundPlayed = false
    self.lastChannelEnd = GetTime()
    self.castEnd = nil
    self.soundCastWaitUntil = nil
    self.bobberCheckStartedAt = nil
    self.bobberMissingSince = nil
    self.bobberBlockedSince = nil
    self.bobberUnknownSince, self.cameraSoftBobberSince = nil, nil
    self.currentRangeDelay = nil
    self.currentRecastDelay = nil
    self.currentHookDelay = nil
    self:RestoreCVars("interactRestore")
    self:FocusSplashSound()
    self:ApplyBindings()
    self:TraceTransition("channel stop (" .. (reason or "state change") .. "); time left " .. remaining .. "; binding " .. BindingAction(self.db.key))
    self:RefreshUI()
    self:SyncFishingSounds()
end

function FF:LureSeconds()
    if GetWeaponEnchantInfo then
        local has, remaining = GetWeaponEnchantInfo()
        if has then
            remaining = tonumber(remaining)
            return remaining and math.max(0, remaining / 1000) or nil
        end
        return 0
    end
    if C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
        local info = C_PaperDollInfo.GetTemporaryEnchantmentInfo(16)
        if not info then return 0 end
        if type(info) == "table" then
            if info.hasEnchant == false then return 0 end
            local remaining = info.expiration or info.expirationTime or info.remainingTime
            remaining = tonumber(remaining)
            if remaining then return math.max(0, remaining / 1000) end
        end
    end
    return nil
end

-- Only replaceable discovery/presentation work belongs here. Gameplay events,
-- saved catch facts, bindings and profession ownership always run immediately.
function FF:DeferScanRefresh(method, urgent)
    local pending = self.scanRefreshPending
    if urgent or not (self.IsCameraSearchBusy and self:IsCameraSearchBusy())
        or not (C_Timer and C_Timer.After) then
        if pending then pending[method] = nil end
        return false
    end
    if not pending then pending = {}; self.scanRefreshPending = pending end
    if not pending[method] then
        pending[method] = true
        local cast = self.cameraCast
        if cast then cast.deferredRefreshes = (cast.deferredRefreshes or 0) + 1 end
    end
    if not self.scanRefreshPump then
        self.scanRefreshPump = function()
            self.scanRefreshScheduled = nil
            if not next(self.scanRefreshPending) then return end
            if not self:IsCameraSearchBusy() then
                -- Discovery precedes its views; drain at most one job per tick.
                local key = self.scanRefreshPending.RefreshMasterChefCookingFromEvent
                    and "RefreshMasterChefCookingFromEvent" or next(self.scanRefreshPending)
                self.scanRefreshPending[key] = nil
                if self[key] then self[key](self) end
            end
            if next(self.scanRefreshPending) and not self.scanRefreshScheduled then
                self.scanRefreshScheduled = true
                C_Timer.After(0.1, self.scanRefreshPump)
            end
        end
    end
    if not self.scanRefreshScheduled then
        self.scanRefreshScheduled = true
        C_Timer.After(0.1, self.scanRefreshPump)
    end
    return true
end

function FF:RefreshUI(skipJournal)
    if self.UpdateUI then self:UpdateUI(skipJournal) end
end

function FF:ToggleMainWindow()
    if self.ToggleUI then self:ToggleUI() end
end

function FF:HandleLauncherClick(mouseButton)
    if IsControlKeyDown and IsControlKeyDown() then return end
    if mouseButton == "RightButton" then
        self:ShowSettings()
    else
        self:ToggleMainWindow()
    end
end

function FF:ResetAllData()
    if not SafeOutOfCombat() then
        self:Print(FF:LocalizedText("reset.all-combat"))
        return
    end
    self:SuspendFishingSounds()
    self:RestoreCVars("interactRestore")
    self:RestoreCVars("bobberIconRestore")
    self:RestoreCVars("soundRestore")
    self:RestoreCVars("backgroundFPSRestore")
    self:RestoreCVars("autoLootRestore")
    self:RestoreCVars("cameraDistanceRestore")
    self:ReleaseFishingFOV(true)
    if self.ReleaseFishingUIVisibility then self:ReleaseFishingUIVisibility(true) end
    -- Keep self.db until the reload completes: PLAYER_LOGOUT still uses it.
    -- The fresh global is the only table WoW will save for the next login.
    ForeverFishingDB = {}
    if ReloadUI then
        local ok = pcall(ReloadUI)
        if ok then return end
    end
    self:Print(FF:LocalizedText("reset.reload-needed"))
end

-- Seed only fresh/reset settings: missing values in existing saves can mean
-- deliberately cleared bindings or a retained legacy view preference.
function FF:ResetFishingInputViewDefaults()
    self.db.actionBindings = { jump="SHIFT-SPACE", recast="CTRL-SPACE" }
    self.db.fishingInformation = { progressMode="hidden" }
    self.db.fishingChatMode = "whispers"
end

function FF:ResetSettingsToDefaults()
    if not SafeOutOfCombat() then
        self:Print(FF:LocalizedText("reset.settings-combat"))
        return
    end
    self.db.uiSchemaVersion = UI_SCHEMA_VERSION
    self.db.key = DEFAULT_FISHING_KEY
    self.db.keyInitialized = true
    self.db.rightClickFishing = nil -- Retired development mode.
    self:ResetFishingInputViewDefaults()
    self.db.language = nil
    self.db.showMinimapIcon = nil
    if self.SyncMinimapIconVisibility then self:SyncMinimapIconVisibility() end
    self.db.interactAssist = true
    self.soundFocusSession = nil
    self:RestoreCVars("soundRestore")
    self.db.soundFocusVolumes = nil
    self.db.soundFocus = true
    self.db.hideLureGlowWhenOutOfLures = true
    self.db.autoEquipGear = true
    self.db.autoEquipLures = true
    self.db.manualGearAndLures = nil
    self.db.autoOpenFishingBar = true
    self.db.autoRestoreGear = true
    self.db.journalFaction = "Auto"
    self.db.campMilestones = true
    self.db.journalTextScale = 1
    self.db.iconBarSpacing = nil
    self.db.fishingBarMode, self.db.lastCompactBarMode = nil,nil
    self.db.fishingBarOrientation,self.db.fishingBarAutoCollapse,self.db.flyoutGrid=nil,nil,nil
    self.db.showUtilityButton,self.db.utilityItems,self.db.utilityHidden=nil,nil,nil
    if self.utilityPicker and not (InCombatLockdown and InCombatLockdown()) then self.utilityPicker:Hide() end
    self.db.minimalFishingCastView=nil
    self.db.showFishingMinimap=nil
    if self.ApplyFishingInformationLayout then self:ApplyFishingInformationLayout() end
    self.db.flyoutLayouts = nil
    self.db.flyoutDefaults = nil
    self.db.fastAutoLoot = true
    self.db.catchRecap = true
    if self.SetHideBlizzardUIWhileFishing then self:SetHideBlizzardUIWhileFishing(false) end
    if self.HideCatchRecap then self:HideCatchRecap() end
    self.db.cameraAssist = false
    self.db.cameraModeDefaultsVersion = 2
    self:ResetScanSettings()
    self.db.rangeSound = "ping"
    self.db.rangeSoundLoop = true
    self.db.recastReminderSound = "off"
    self.db.catchConfirmedSound = "off"
    self.db.fishEscapedSound = "off"
    self.db.cookingCompleteSound = "chime"
    self.db.enableAlertSounds = true
    self.db.recastReminderLoop = false
    self.db.recastReminderDelay = self.recastReminderTiming.default
    self.db.soundRepeatInterval = self.soundRepeatTiming.default
    self.db.voiceVolume = self.voiceVolumeTiming.default
    self.db.voiceVolumeDefaultVersion = 1
    self:StopFishingSounds()
    self:SyncFishingSounds()
    self:ResetTimingProfiles()
    self.db.timingDefaultsVersion = 2
    if self.ResetFishingLayouts then self:ResetFishingLayouts() end
    if self.ApplyIconBarSpacing then self:ApplyIconBarSpacing() end
    if self.ApplyJournalTextSize then self:ApplyJournalTextSize() end
    if self.RefreshFishingFlyoutLayout then
        for _, kind in ipairs({ "gear", "lure", "chef", "utility" }) do
            self:RefreshFishingFlyoutLayout(kind)
        end
    end
    if self.StopCameraAssist then self:StopCameraAssist("Settings reset", true) end
    self:SyncFishingFOV()
    if self.active then self:PrepareInteract() end
    self:FocusSplashSound()
    self:ApplyBindings()
    self:RefreshUI()
    if self.settingsPanel then self:ShowSettings() end
    self:Print(FF:LocalizedText("reset.settings-done"))
end

function FF:ShowSettingsResetConfirmation()
    if not SafeOutOfCombat() then
        self:Print(FF:LocalizedText("reset.settings-combat"))
        return
    end
    if not StaticPopupDialogs or not StaticPopup_Show then
        self:Print(FF:LocalizedText("reset.settings-unavailable"))
        return
    end
    local key = "FOREVER_FISHING_RESET_SETTINGS"
    if not StaticPopupDialogs[key] then
        StaticPopupDialogs[key] = {
            text = FF:LocalizedText("reset.settings-confirm"),
            button1 = FF:LocalizedText("reset.settings-button"),
            button2 = FF:LocalizedText("reset.clear-all-button"),
            extraButton = CANCEL or FF:LocalizedText("binding.cancel"),
            selectCallbackByIndex = true,
            OnButton1 = function() FF:ResetSettingsToDefaults() end,
            OnButton2 = function()
                StaticPopup_Hide(key)
                FF:ShowResetConfirmation()
            end,
            OnExtraButton = function() end,
            OnShow = function(dialog)
                if not (dialog.ButtonContainer and dialog.Text and dialog.ExtraButton) then return end
                dialog.ButtonContainer:ClearAllPoints()
                dialog.ButtonContainer:SetPoint("TOP", dialog.Text, "BOTTOM", 0, -17)
                if dialog.Separator then dialog.Separator:Hide() end
                dialog.ExtraButton:ClearAllPoints()
                dialog.ExtraButton:SetPoint("TOP", dialog.ButtonContainer, "BOTTOM", 0, -10)
            end,
            OnHide = function(dialog)
                FF:ReleaseFishingResetPopup(dialog)
                if not (dialog.ExtraButton and dialog.Separator) then return end
                dialog.ExtraButton:ClearAllPoints()
                dialog.ExtraButton:SetPoint("TOP", dialog.Separator, "BOTTOM", 0, -13)
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end
    self:ShowFishingResetPopup(key)
end

function FF:ShowResetConfirmation()
    if not SafeOutOfCombat() then
        self:Print(FF:LocalizedText("reset.all-combat"))
        return
    end
    if not StaticPopupDialogs or not StaticPopup_Show then
        self:Print(FF:LocalizedText("reset.all-unavailable"))
        return
    end
    local key = "FOREVER_FISHING_RESET_ALL"
    if not StaticPopupDialogs[key] then
        StaticPopupDialogs[key] = {
            text = FF:LocalizedText("reset.all-confirm"),
            button1 = FF:LocalizedText("reset.all-button"),
            button2 = CANCEL or FF:LocalizedText("binding.cancel"),
            OnAccept = function() FF:ResetAllData() end,
            OnHide = function(dialog) FF:ReleaseFishingResetPopup(dialog) end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end
    self:ShowFishingResetPopup(key)
end

SLASH_FOREVERFISHING1 = "/fish"
SlashCmdList.FOREVERFISHING = function(message)
    local command, arg = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "bind" then
        FF:BeginKeyCapture(arg ~= "" and arg:lower() or "fishing")
    elseif command == "unbind" then
        FF:SetFishingActionBinding(arg ~= "" and arg:lower() or "fishing", nil)
    elseif command == "pin" then
        FF:Print(FF:LocalizedText("runtime.flyout-help-legacy"))
    elseif command == "gear" then
        FF:ShowGearPicker()
    elseif command == "lure" then
        FF:SetLure(tonumber(arg))
    elseif command == "settings" then
        FF:ShowSettings()
    elseif command == "dev" then
        FF:ShowCameraDeveloper()
    elseif command == "repair" then
        FF.castMacroIndex = FF:EnsureCastMacro()
        FF:RefreshCastMacro()
        FF:RefreshUI()
    elseif command == "status" then
        FF:ShowStatus()
    elseif command == "trace" then
        FF:ShowTrace()
    elseif command == "changes" then
        FF:ShowLayoutChanges()
    elseif command == "reset" then
        FF:ShowResetConfirmation()
    else
        FF:ToggleMainWindow()
    end
end

events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_SPELLCAST_SENT")
events:RegisterEvent("UNIT_SPELLCAST_START")
events:RegisterEvent("UNIT_SPELLCAST_DELAYED")
events:RegisterEvent("UNIT_SPELLCAST_STOP")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_FAILED_QUIET")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:RegisterEvent("UI_INFO_MESSAGE")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
events:RegisterEvent("LOOT_READY")
events:RegisterEvent("LOOT_SLOT_CHANGED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("UNIT_INVENTORY_CHANGED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:RegisterEvent("TRADE_SKILL_CLOSE")
events:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
pcall(events.RegisterEvent, events, "UPDATE_TRADESKILL_CAST_STOPPED")
pcall(events.RegisterEvent, events, "NEW_RECIPE_LEARNED")
pcall(events.RegisterEvent, events, "TRADE_SKILL_UPDATE")
pcall(events.RegisterEvent, events, "TRADE_SKILL_DATA_SOURCE_CHANGED")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("UPDATE_MACROS")
events:RegisterEvent("CVAR_UPDATE")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
events:SetScript("OnEvent", function(_, event, unit, target, castGUID, spellID)
    -- Support legacy message-only errors alongside (errorID, message).
    if event == "UI_ERROR_MESSAGE" and type(target) ~= "string" and type(unit) == "string"
        and not (issecretvalue and issecretvalue(unit)) then
        target, unit = unit, nil
    end
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        FF:UpdateFishingVisibilityRoot()
        if FF.ApplyIconBarSpacing then FF:ApplyIconBarSpacing() end
        return
    elseif event == "ADDON_LOADED" then
        if FF.db and FF.InstallBlizzardPanelHooks then FF:InstallBlizzardPanelHooks() end
        if FF.db and FF.InstallFishingTemporaryPanelHooks then FF:InstallFishingTemporaryPanelHooks() end
        if FF.db and FF.RegisterAuctionPriceUpdates then FF:RegisterAuctionPriceUpdates() end
        return
    elseif event == "PLAYER_LOGIN" then
        if type(ForeverFishingDB) ~= "table" then ForeverFishingDB = {} end
        FF.db = ForeverFishingDB
        local hadSavedState = next(FF.db) ~= nil
        FF.masterChefCookingQueue = {}
        FF.masterChefCampCraftQueue = {}
        if type(FF.db.launcher) ~= "table" then FF.db.launcher = {} end
        if type(FF.db.journal) ~= "table" then FF.db.journal = {} end
        FF:InitializeLifetimeStats()
        FF:RegisterAuctionPriceUpdates()
        FF:RestoreCVars("interactRestore")
        FF:RestoreCVars("bobberIconRestore")
        FF:RestoreCVars("soundRestore")
        FF:RestoreCVars("backgroundFPSRestore")
        FF:RestoreCVars("autoLootRestore")
        FF:RestoreCVars("cameraCenterRestore")
        FF:RestoreCVars("cameraViewBlendRestore")
        FF:RestoreCVars("cameraZoomRestore")
        FF:RestoreCVars("cameraDistanceRestore")
        FF:ReleaseFishingFOV(true)
        -- Restore addon-owned game state before the one-time settings upgrade;
        -- build every setting and frame from the new UI schema afterward.
        if FF:InitializeSavedVariableSchemaVersions(hadSavedState) then FF:ResetFishingInputViewDefaults() end
        FF:InitializeLocalization()
        if FF.db.keyInitialized == nil then
            if FF.db.key == nil then FF.db.key = DEFAULT_FISHING_KEY end
            FF.db.keyInitialized = true
        end
        FF.db.interactAssist = true
        if FF.db.soundFocus == nil then FF.db.soundFocus = true end
        if FF.db.hideLureGlowWhenOutOfLures == nil then FF.db.hideLureGlowWhenOutOfLures = true end
        local wasAutomatic = FF.db.manualGearAndLures ~= true
        if FF.db.autoEquipGear == nil then FF.db.autoEquipGear = wasAutomatic end
        if FF.db.autoEquipLures == nil then FF.db.autoEquipLures = wasAutomatic end
        FF.db.manualGearAndLures = nil
        if FF.db.autoOpenFishingBar == nil then FF.db.autoOpenFishingBar = true end
        if FF.db.autoRestoreGear == nil then FF.db.autoRestoreGear = true end
        if FF.db.journalFaction ~= "Alliance" and FF.db.journalFaction ~= "Horde" then
            FF.db.journalFaction = "Auto"
        end
        if FF.db.campMilestones == nil then FF.db.campMilestones = true end
        if FF.db.fastAutoLoot == nil then FF.db.fastAutoLoot = true end
        if FF.db.catchRecap == nil then FF.db.catchRecap = true end
        if FF.db.hideBlizzardUIWhileFishing == nil then FF.db.hideBlizzardUIWhileFishing = false end
        FF:InitializeFishingViewSettings()
        FF:InitializeFishingActionBindings()
        FF:InitializeFishingMode()
        FF:InitializeScanConfig()
        FF.db.lureWarning = nil
        FF:InitializeSoundSettings()
        local timing = FF.timing
        if (tonumber(FF.db.timingDefaultsVersion) or 0) < 2 then
            if tonumber(FF.db.recastDelay) == 2.5 then FF.db.recastDelay = timing.recastDefault end
            if tonumber(FF.db.hookDelay) == 2.5 then FF.db.hookDelay = timing.hookDefault end
            if tonumber(FF.db.pressLock) == 0.25 then FF.db.pressLock = timing.pressDefault end
            FF.db.timingDefaultsVersion = 2
        end
        FF.db.rangeDelay = ClampTwentieth(FF.db.rangeDelay, timing.rangeMin, timing.rangeMax, timing.rangeDefault)
        FF.db.recastDelay = ClampTenth(FF.db.recastDelay, timing.recastMin, timing.recastMax, timing.recastDefault)
        FF.db.hookDelay = ClampTenth(FF.db.hookDelay, timing.hookMin, timing.hookMax, timing.hookDefault)
        FF.db.pressLock = ClampTwentieth(FF.db.pressLock, timing.pressMin, timing.pressMax, timing.pressDefault)
        FF:InitializeTimingProfiles()
        if FF.InitializeFishingSystems then FF:InitializeFishingSystems() end
        if FF.RefreshFishingAchievements then FF:RefreshFishingAchievements(false, true) end
        if FF.QueueNormalWeaponCapture then FF:QueueNormalWeaponCapture() end
        FF.castMacroIndex = FF:EnsureCastMacro()
        FF:InitializeUI()
        FF:InitializeCameraScanning()
        FF:InstallBlizzardPanelHooks()
        FF:ApplyBindings()
        FF:CheckFishingRodAutoOpen(true)
        if IsFishingChannel() then FF:StartChannel(true) end
        local launcher = _G.ForeverAddonLauncher
        if launcher and launcher.RegisterAddon then
            launcher:RegisterAddon("ForeverFishing", {
                title = "Forever Fishing",
                subtitle = FF.LocalizedText and FF:LocalizedText("launcher.subtitle") or "Fishing tools & journal",
                icon = FF.icon,
                storage = FF.db.launcher,
                open = function() FF:ShowSettings() end,
                listClick = function(mouseButton) FF:HandleLauncherClick(mouseButton) end,
                individualClick = function(mouseButton) FF:HandleLauncherClick(mouseButton) end,
                displayText = FF:GetLauncherDisplayText(),
                combatClickTarget = FF.closeButton,
                combatClickSession = FF.bar,
                listHint = FF.LocalizedText and FF:LocalizedText("launcher.hint") or "Left: fishing bar  |  Right: settings",
                individualHint = FF.LocalizedText and FF:LocalizedText("launcher.hint") or "Left: fishing bar  |  Right: settings",
            })
            if hooksecurefunc then
                hooksecurefunc(launcher, "RefreshButtons", function()
                    FF:UpdateLauncherIndividualIcon(launcher)
                end)
            end
            FF:UpdateLauncherIndividualIcon(launcher)
            FF:SyncMinimapIconVisibility()
        end
        return
    elseif event == "PLAYER_LEAVING_WORLD" then
        if FF.InterruptKeyCapture then FF:InterruptKeyCapture() end
        FF:RestoreCVars("bobberIconRestore")
        if FF.SuspendGearOperation then FF:SuspendGearOperation() end
        if FF.InvalidateMasterChefRecipeCatalogs then FF:InvalidateMasterChefRecipeCatalogs() end
        if FF.ReleaseMasterChefCampSession then FF:ReleaseMasterChefCampSession() end
        if FF.masterChefCookingActive then
            local quick = FF.masterChefCookingQuickActive
            FF.masterChefCookingActive = nil
            FF.masterChefCookingRemaining = nil
            FF.masterChefCraftToken = (FF.masterChefCraftToken or 0) + 1
            if quick then
                FF:SetMasterChefMessage("masterChefQuickMessage", "chef.message.cooking-stopped-click")
            else
                FF:SetMasterChefMessage("masterChefQueueMessage", "chef.message.cooking-stopped-start")
            end
        end
        if FF.ReleaseMasterChefCookingSession then FF:ReleaseMasterChefCookingSession() end
        FF:RestoreCVars("cameraCenterRestore")
        FF:RestoreCVars("cameraViewBlendRestore")
        FF:RestoreCVars("cameraZoomRestore")
        FF:RestoreCVars("cameraDistanceRestore")
        FF:ReleaseFishingFOV(true)
        FF:SuspendFishingSounds()
        FF:FocusSplashSound()
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        FF:SyncBobberInteractIcon()
        FF.gearWorldInterrupted = nil
        if FF.InvalidateMasterChefRecipeCatalogs then FF:InvalidateMasterChefRecipeCatalogs() end
        if FF.RefreshFishingAchievements then FF:RefreshFishingAchievements(false, true) end
        FF.soundAlertsSuspended = false
        FF:SyncLongRangeCameraDistance()
        FF:SyncFishingFOV()
        FF:FocusSplashSound()
        FF:SyncFishingSounds()
        -- Equipped items can become readable after PLAYER_LOGIN on a fresh login.
        -- A repeated check keeps the same-rod guard, so zoning will not reopen
        -- a fishing bar the player closed manually.
        FF:CheckFishingRodAutoOpen(FF.rodAutoOpenItemInfo ~= nil)
        if FF.journalTab == "nearby" and FF.RefreshJournal then FF:RefreshJournal() end
        return
    elseif event == "PLAYER_LOGOUT" then
        if FF.InterruptKeyCapture then FF:InterruptKeyCapture() end
        if FF.SuspendGearOperation then FF:SuspendGearOperation() end
        if FF.CommitOpenFloatingWindowLayouts then FF:CommitOpenFloatingWindowLayouts() end
        if FF.ReleaseMasterChefCampSession then FF:ReleaseMasterChefCampSession() end
        if FF.ReleaseMasterChefCookingSession then FF:ReleaseMasterChefCookingSession() end
        FF:RestoreCVars("cameraCenterRestore")
        FF:RestoreCVars("cameraViewBlendRestore")
        FF:RestoreCVars("cameraZoomRestore")
        FF:RestoreCVars("cameraDistanceRestore")
        FF:SuspendFishingSounds()
        FF:StopCameraMotion()
        FF:ReleaseFishingFOV(true)
        if FF.RememberNormalWeapons then FF:RememberNormalWeapons() end
        FF:AccrueLifetimeFishingTime()
        FF:FinishHistoricalSession("logout")
        FF:RestoreCVars("interactRestore")
        FF:RestoreCVars("bobberIconRestore")
        FF:RestoreCVars("soundRestore")
        FF:RestoreCVars("backgroundFPSRestore")
        FF:RestoreCVars("autoLootRestore")
        if FF.ReleaseFishingUIVisibility then FF:ReleaseFishingUIVisibility(true) end
        return
    end
    if event == "CURRENT_SPELL_CAST_CHANGED" and FF.CheckMasterChefCampPlacement then
        FF:CheckMasterChefCampPlacement(event, unit)
    elseif (event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE") and type(target) == "string"
        and not (issecretvalue and issecretvalue(target)) then
        if event == "UI_ERROR_MESSAGE" then
            local gearHandled = FF.OnGearSwapUIError and FF:OnGearSwapUIError(target, unit)
            if not gearHandled then
                local handled = FF.OnMasterChefCraftUIError and FF:OnMasterChefCraftUIError(target, unit)
                if not handled and FF.OnMasterChefUIError then FF:OnMasterChefUIError(target, unit) end
                if handled and FF.RefreshMasterChefQuickTray then FF:RefreshMasterChefQuickTray() end
            end
        end
        FF:OnFishingEscapeMessage(target)
        local lower = (target:gsub("[A-Z]",string.lower))
        local identity=FF:GetNativeErrorName(unit)
        local nativeRodError=identity=="SPELL_FAILED_EQUIPPED_ITEM_CLASS"
            and FF.lastFishingCastAttemptAt and GetTime()-FF.lastFishingCastAttemptAt<=5
            and FF.FishingRodEquippedNow and FF:FishingRodEquippedNow()==false
        if event == "UI_ERROR_MESSAGE" and (nativeRodError or (lower:find("fishing pole", 1, true) and lower:find("equip", 1, true))) then
            FF:OnFishingRodRequired(true)
        elseif FF:MatchesNativeError(target,{"SPELL_FAILED_NOT_FISHABLE","SPELL_FAILED_TOO_SHALLOW","SPELL_FAILED_NO_FISH"},unit)
            or (target == (SPELL_FAILED_TOO_SHALLOW or "Water too shallow")) then
            FF:OnFishingCastFailed()
        end
    elseif event == "UNIT_SPELLCAST_SENT" and unit == "player" then
        if FF.OnAchievementLureEvent then FF:OnAchievementLureEvent(event, spellID, castGUID) end
        FF:OnFishingCastSent(spellID)
        if FF.OnMasterChefCraftSent then FF:OnMasterChefCraftSent(spellID, castGUID) end
    elseif event == "UNIT_SPELLCAST_FAILED_QUIET" and unit == "player" then
        if FF.OnAchievementLureEvent then FF:OnAchievementLureEvent(event, castGUID, target) end
        -- Quiet rejection is a terminal craft failure too; keep this separate
        -- from the fishing/lure routing of ordinary cast events.
        if FF.OnMasterChefCraftFailed then FF:OnMasterChefCraftFailed(castGUID, target) end
        if FF.OnMasterChefCampCraftEvent then
            FF:OnMasterChefCampCraftEvent("UNIT_SPELLCAST_FAILED", castGUID, target)
        end
        if FF.RefreshMasterChefQuickTray then FF:RefreshMasterChefQuickTray() end
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" and unit == "player" then
        local active,started,ends=IsFishingChannel()
        if FF.active and active and started==FF.castStart then
            FF.castEnd=ends or FF.castEnd
            if FF.UpdateFishingInformation then FF:UpdateFishingInformation() end
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" and unit == "player" then
        FF:StartChannel(nil, target, castGUID)
    elseif (event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED") and unit == "player" then
        if FF.OnAchievementLureEvent then FF:OnAchievementLureEvent(event, castGUID, target) end
        FF:StopChannel(event, target, castGUID)
        if FF.ShowNextAchievementNotice then FF:ShowNextAchievementNotice() end
        if event == "UNIT_SPELLCAST_INTERRUPTED" then
            if FF.OnMasterChefCampCraftEvent then FF:OnMasterChefCampCraftEvent(event, castGUID, target) end
            if FF.OnMasterChefCampPlacementEvent then FF:OnMasterChefCampPlacementEvent(event, castGUID) end
        end
        if event == "UNIT_SPELLCAST_INTERRUPTED" and FF.OnMasterChefCraftFailed then
            FF:OnMasterChefCraftFailed(castGUID, target)
        end
        if FF.lureApplyPendingAt then
            if event == "UNIT_SPELLCAST_INTERRUPTED" then FF.lureApplyPendingAt = nil end
            FF:RefreshUI()
        end
    elseif (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_SUCCEEDED") and unit == "player" then
        -- UNIT_SPELLCAST_* uses (unit, castGUID, spellID, castBarID).
        -- SENT instead has a target before the cast GUID.
        local failedSpellID = castGUID or spellID
        if FF.OnAchievementLureEvent then FF:OnAchievementLureEvent(event, failedSpellID, target) end
        if event == "UNIT_SPELLCAST_START" and FF.OnMasterChefCraftStarted then
            FF:OnMasterChefCraftStarted(failedSpellID, target)
        end
        if FF.OnMasterChefCampCraftEvent then FF:OnMasterChefCampCraftEvent(event, failedSpellID, target) end
        if FF.OnMasterChefCampPlacementEvent then FF:OnMasterChefCampPlacementEvent(event, failedSpellID) end
        if event == "UNIT_SPELLCAST_SUCCEEDED" and FF.OnMasterChefCraftSucceeded then
            FF:OnMasterChefCraftSucceeded(failedSpellID, target)
        elseif event == "UNIT_SPELLCAST_FAILED" and FF.OnMasterChefCraftFailed then
            FF:OnMasterChefCraftFailed(failedSpellID, target)
        end
        if (event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED")
            and FF.RefreshMasterChefQuickTray then FF:RefreshMasterChefQuickTray() end
        if event == "UNIT_SPELLCAST_FAILED" and FF.soundCastPending and type(failedSpellID) == "number"
            and not (issecretvalue and issecretvalue(failedSpellID))
            and (failedSpellID == 7620 or failedSpellID == FISHING_SPELL or failedSpellID == FISHING_CAST) then
            FF:OnFishingCastFailed()
        end
        local pendingLure = FF.lureApplyPendingAt
        if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
            or (event == "UNIT_SPELLCAST_SUCCEEDED" and not (UnitCastingInfo and UnitCastingInfo("player"))) then
            FF.lureApplyPendingAt = nil
        end
        if pendingLure or (FF.db and (FF.db.autoEquipGear or FF.db.autoEquipLures)
            and FF.bar and FF.bar:IsShown()) then FF:RefreshUI() end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" or event == "LOOT_SLOT_CHANGED" then
        FF:RecordLoot()
        if event == "LOOT_READY" then FF:FastLootFishingItems(unit) end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if FF.JournalFoodItemDataReceived then FF:JournalFoodItemDataReceived(unit,target) end
        FF.combatWeaponPlanDirty = true
        FF:RefreshCatchItemName(unit, target)
        if target and FF.RefreshCatchRecapItem then FF:RefreshCatchRecapItem(unit) end
        local qualityRequested = FF.requestedCatchQualityItems and FF.requestedCatchQualityItems[unit]
        if qualityRequested then FF.requestedCatchQualityItems[unit] = nil end
        if not target and FF.requestedCatchValueItems then FF.requestedCatchValueItems[unit] = nil end
        if target and FF.db and FF.db.journal and FF.db.journal[unit] then
            FF:InvalidateFishingStats()
            FF:RefreshJournal()
        end
        if qualityRequested and target and FF.RefreshCatchItemQuality then FF:RefreshCatchItemQuality(unit) end
        if unit == FF.rodAutoOpenItemInfo then
            FF.rodAutoOpenItemInfo = nil
            if target then FF:CheckFishingRodAutoOpen(true) end
        end
    elseif event == "LOOT_CLOSED" then
        FF:CloseFishingLoot()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if FF.gearOperation then FF:StopLocalizedGearOperation(FF.gearOperation,
            "gear.failure.combat") end
        if FF.InterruptKeyCapture then FF:InterruptKeyCapture() end
        if FF.HideAchievementNotice then FF:HideAchievementNotice() end
        if FF.SuspendMasterChefPreparation then FF:SuspendMasterChefPreparation("combat") end
    elseif event == "UPDATE_BINDINGS" then
        if not FF.db or not SafeOutOfCombat() then return end
        FF:ApplyBindings()
        if FF.settingsPanel and FF.settingsPanel.RefreshBindingControls then FF.settingsPanel:RefreshBindingControls() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if FF.pendingFishingBarClose and FF.FinishFishingBarClose then FF:FinishFishingBarClose() end
        -- Reconcile current channel/session intent before draining old CVar
        -- ownership; never restore underneath a newer active fishing channel.
        if FF.active and FF.db and FF.db.interactAssist ~= false and FF.bar and FF.bar:IsShown() then
            FF:PrepareInteract()
        else
            FF:RestoreCVars("interactRestore")
        end
        if FF.pendingSettingsMenuClose then
            FF.pendingSettingsMenuClose:Hide()
            FF.pendingSettingsMenuClose = nil
        end
        if FF.ApplyPendingFishingLayouts then FF:ApplyPendingFishingLayouts() end
        if FF.RegisterPendingCombatCloseWindows then FF:RegisterPendingCombatCloseWindows() end
        if FF.ResumeMasterChefWindowClose then FF:ResumeMasterChefWindowClose() end
        if FF.ResumeFishingUIVisibility then FF:ResumeFishingUIVisibility() end
        if FF.ShowPendingJournalPresentation then FF:ShowPendingJournalPresentation() end
        if FF.ShowNextAchievementNotice then FF:ShowNextAchievementNotice() end
        FF:TryFishingRodAutoOpen()
        FF:RefreshFishingLayer()
        if FF.active and FF.UpdateBobberStatus then FF:UpdateBobberStatus() end
        FF:RefreshCastMacro()
        FF:ApplyBindings()
        if FF.SyncCastAction then FF:SyncCastAction() end
        FF:RefreshUI()
        if FF.RefreshMasterChefQuickTray then FF:RefreshMasterChefQuickTray() end
    elseif event == "CVAR_UPDATE" then
        FF:SplashSoundCVarChanged(unit)
        FF:AutoLootCVarChanged(unit)
        FF:CameraCVarChanged(unit)
        if FF.active and type(unit) == "string" and FF.castStart and GetTime() - FF.castStart > 0.2 then
            local name = unit:lower()
            if name == "softtargetinteract" or name == "softtargetinteractarc" or name == "softtargetinteractrange" then
                FF:TraceTransition("interact setting changed: " .. unit .. "=" .. (ReadCVar(unit) or "?"))
            end
        end
        if type(unit) == "string" and unit:lower() == BACKGROUND_SOUND_CVAR:lower() and FF.RefreshBackgroundSoundSetting then
            FF:RefreshBackgroundSoundSetting()
        end
        if type(unit) == "string" and FF.RefreshGameSoundSliders then
            local name = unit:lower()
            if name == "sound_mastervolume" or name == "sound_ambiencevolume" or name == "sound_musicvolume" then
                FF:RefreshGameSoundSliders()
            end
        end
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        if FF.active and FF.UpdateBobberStatus then FF:UpdateBobberStatus() end
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
        FF.journalLocationRevision = (FF.journalLocationRevision or 0) + 1
        if FF.journalPanel and FF.journalPanel:IsShown() then FF:RefreshJournal() end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if unit == "player" then
            FF:CheckFishingRodAutoOpen(FF.rodAutoOpenItemInfo ~= nil)
            if FF.SyncSessionRodTime then FF:SyncSessionRodTime() end
            FF:RefreshUI()
        end
    elseif event == "PLAYER_LEVEL_UP" then
        if FF.UpdateFishingInformation then FF:UpdateFishingInformation(true, unit) end
    elseif event == "SKILL_LINES_CHANGED" or (event == "UNIT_AURA" and unit == "player") then
        if FF.UpdateFishingInformation then FF:UpdateFishingInformation(true) end
        if event == "SKILL_LINES_CHANGED" then FF.journalSearchIndexRevision = nil end
        if event == "SKILL_LINES_CHANGED" and FF.InvalidateMasterChefRecipeCatalogs then FF:InvalidateMasterChefRecipeCatalogs() end
        if event == "SKILL_LINES_CHANGED" and FF.ScanMasterChefCooking then FF:ScanMasterChefCooking() end
        if event == "SKILL_LINES_CHANGED" and FF.RefreshFishingAchievements then FF:RefreshFishingAchievements(true, true) end
        if FF.RefreshJournal then FF:RefreshJournal() end
        if event == "SKILL_LINES_CHANGED" and FF.RefreshMasterChefQuickTray then
            FF:RefreshMasterChefQuickTray()
        end
    elseif event == "TRADE_SKILL_CLOSE" then
        if FF.InvalidateMasterChefRecipeCatalogs then FF:InvalidateMasterChefRecipeCatalogs() end
        if FF.OnMasterChefCampSessionEvent then FF:OnMasterChefCampSessionEvent(event) end
        if FF.OnMasterChefCookingSessionClosed then FF:OnMasterChefCookingSessionClosed() end
    elseif event == "UPDATE_TRADESKILL_CAST_STOPPED" then
        if FF.OnMasterChefCraftStopped then FF:OnMasterChefCraftStopped() end
        if FF.OnMasterChefCampCraftStopped then FF:OnMasterChefCampCraftStopped() end
    elseif event == "NEW_RECIPE_LEARNED" or event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE"
        or event == "TRADE_SKILL_UPDATE"
        or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        FF.journalSearchIndexRevision = nil
        if FF.InvalidateMasterChefRecipeCatalogs then FF:InvalidateMasterChefRecipeCatalogs() end
        if FF.OnMasterChefCampSessionEvent then FF:OnMasterChefCampSessionEvent(event) end
        if FF.RefreshMasterChefCookingFromEvent then FF:RefreshMasterChefCookingFromEvent() end
        if FF.RefreshFishingAchievements then FF:RefreshFishingAchievements(true, true) end
        if FF.ReviewMasterChefCookingSession then FF:ReviewMasterChefCookingSession(event) end
        if FF.RefreshMasterChefQuickTray then FF:RefreshMasterChefQuickTray() end
    elseif event == "BAG_UPDATE_DELAYED" then
        FF.combatWeaponPlanDirty = true
        if FF.ScanFishingInventory then FF:ScanFishingInventory() end
        FF:RefreshUI(true)
        if FF.RefreshJournal then FF:RefreshJournal() end
        if FF.RefreshMasterChefQuickTray then FF:RefreshMasterChefQuickTray() end
    elseif event == "UPDATE_MACROS" then
        FF:RefreshCastMacro()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        FF.combatWeaponPlanDirty = true
        if FF.OnGearEquipmentChanged then FF:OnGearEquipmentChanged(unit) end
        if unit == 16 then
            FF:CheckFishingRodAutoOpen()
            if FF.SyncSessionRodTime then FF:SyncSessionRodTime() end
            -- A manually equipped pole may already be on an open bar. Save its
            -- restore pair before a later manual weapon change replaces it.
            if FF.bar and FF.bar:IsShown() and FF.RememberWornFishingGear then FF:RememberWornFishingGear(true) end
        end
        if (unit == 16 or unit == 17) and FF.QueueNormalWeaponCapture then FF:QueueNormalWeaponCapture() end
        FF:RefreshUI()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        FF.combatWeaponPlanDirty = true
        if FF.QueueNormalWeaponCapture then FF:QueueNormalWeaponCapture() end
    elseif event == "EQUIPMENT_SWAP_FINISHED" then
        FF.combatWeaponPlanDirty = true
        if (unit == true or unit == 1) and FF.QueueNormalWeaponCapture then FF:QueueNormalWeaponCapture(target) end
    elseif event == "EQUIPMENT_SETS_CHANGED" then
        FF.combatWeaponPlanDirty = true
        if FF.QueueNormalWeaponCapture then FF:QueueNormalWeaponCapture() end
    end
end)
