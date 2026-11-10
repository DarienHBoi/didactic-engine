-------------------------------------------------------------------------------
-- AnimatedBlizzPortrait
-- Replaces every Blizzard unit-frame portrait with a live 3D animated model.
-- /abp → tabbed settings panel
-------------------------------------------------------------------------------

local ABP = {} -- Client support versions are declared in the TOC.
AnimatedBlizzPortrait = ABP

local CLIENT_BUILD = select(4, GetBuildInfo()) or 0
-- Hybrid/fan clients (e.g. "WoW Forever") run on a retail-based executable but
-- can report odd/older build numbers, which used to misclassify them as
-- Classic and disable most options. WOW_PROJECT_MAINLINE is a reliable signal
-- that the client is retail-based regardless of its reported build number.
local isMainlineProject = WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
ABP.isModernClient = CLIENT_BUILD >= 120000 or isMainlineProject
ABP.isClassicClient = CLIENT_BUILD < 40000 and not isMainlineProject
ABP.supportsCustomFrameOptions = not ABP.isClassicClient
ABP.portraits      = {}
ABP.runway         = {}
ABP.barColorTick   = 0
ABP.barColorBurstUntil = 0

local MEDIA_ROOT = "Interface\\AddOns\\AnimatedBlizzPortrait\\media\\"
local ABP_MEDIA = {
    fonts = {
        condensed = MEDIA_ROOT .. "fonts\\Myriad Condensed Web.ttf",
    },
    textures = {
        smooth = MEDIA_ROOT .. "textures\\smooth.tga",
        smoother = MEDIA_ROOT .. "textures\\smoother.tga",
        charcoal = MEDIA_ROOT .. "textures\\Charcoal.tga",
        minimalist = MEDIA_ROOT .. "textures\\Minimalist.tga",
        aluminium = MEDIA_ROOT .. "textures\\Aluminium.tga",
        liteStep = MEDIA_ROOT .. "textures\\LiteStep.tga",
        striped = MEDIA_ROOT .. "textures\\striped.tga",
        smoothv2 = MEDIA_ROOT .. "textures\\Smoothv2.tga",
        highlight = MEDIA_ROOT .. "textures\\highlight.tga",
        combo = MEDIA_ROOT .. "textures\\combo.tga",
        borderDark = MEDIA_ROOT .. "textures\\border-dark.tga",
        borderLight = MEDIA_ROOT .. "textures\\border-light.tga",
    },
}
ABP.media = ABP_MEDIA

-- Validate the custom font once at load time. ABP_MEDIA.fonts.condensed is
-- always a truthy string, so "path or STANDARD_TEXT_FONT" would never fall
-- back even when the TTF fails to load. Use GetFont() to confirm the load.
local ABP_UI_FONT = (function()
    local probe = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local ok = probe:SetFont(ABP_MEDIA.fonts.condensed, 12, "")
    local actual = probe:GetFont()
    -- A failed SetFont leaves the previous font in place, so GetFont() returning
    -- something non-empty proves nothing — it is just GameFontNormal's path.
    -- Compare what actually stuck against what we asked for; otherwise the
    -- fallback never fires and every SetFont(ABP_UI_FONT, ...) silently no-ops.
    local loaded = (ok ~= false)
        and type(actual) == "string"
        and actual:lower() == ABP_MEDIA.fonts.condensed:lower()
    return loaded and ABP_MEDIA.fonts.condensed or STANDARD_TEXT_FONT
end)()

local WHITE_TEX = "Interface\\Buttons\\WHITE8X8"
local MODERN_BG = { 0.025, 0.033, 0.043, 0.94 }
local MODERN_PANEL = { 0.045, 0.060, 0.078, 0.88 }
local MODERN_FIELD = { 0.032, 0.043, 0.058, 0.96 }
local MODERN_TEXT = { 0.86, 0.90, 0.95, 1.00 }
local MODERN_MUTED = { 0.58, 0.64, 0.72, 1.00 }
local MODERN_BORDER = { 0.22, 0.31, 0.40, 1.00 }

-- Internal constants (never change at runtime)
local ANIM = 804
local MIN_SIZE = 18
-- Keep unit-frame artwork below normal UI panels (bags, map, menus).  Frame
-- levels still let the portrait sit above Blizzard's bars within MEDIUM strata.
local UNIT_ART_STRATA = "MEDIUM"
local UNIT_ART_LEVEL_OFFSET = 10
local UNIT_OVERLAY_LEVEL_OFFSET = 30

local function SetUnitOverlayLayer(frame)
    if not frame then return end
    frame:SetFrameStrata(UNIT_ART_STRATA)
    local parent = frame:GetParent()
    if parent and parent.GetFrameLevel and frame.SetFrameLevel then
        frame:SetFrameLevel(math.max(frame:GetFrameLevel(),
            parent:GetFrameLevel() + UNIT_OVERLAY_LEVEL_OFFSET))
    end
end
local BG_NAMES         = { "Transparent", "Black", "Class Color", "Custom" }
local BORDER_NAMES     = { "Transparent", "Slate", "Silver", "Class Color", "Custom" }
local BAR_BORDER_NAMES = { "Transparent", "Slate", "Silver", "Custom" }
local BAR_COLOR_NAMES  = { "Default", "Solid", "Gradient", "Class Color" }
local NAME_HIGHLIGHT_NAMES = { "Default", "Transparent", "Class Color", "Custom" }
local NAME_TEXT_NAMES = { "Default", "Custom", "Class Color" }
local RUNE_STYLE_NAMES = { "Auto", "Classic", "Blood", "Frost", "Unholy", "Death" }
local COMBO_STYLE_NAMES = { "Classic", "Strike", "Skull", "Shadow" }
local CLASS_POWER_SHAPE_NAMES = { "Square", "Circle" }
local BAR_TEXTURE_NAMES = { "Smooth", "Smoother", "Minimal", "Charcoal", "Lite", "Striped" }
local BAR_TEXTURE_PATHS = {
    ABP_MEDIA.textures.smooth or WHITE_TEX,
    ABP_MEDIA.textures.smoother or WHITE_TEX,
    ABP_MEDIA.textures.minimalist or WHITE_TEX,
    ABP_MEDIA.textures.charcoal or WHITE_TEX,
    ABP_MEDIA.textures.liteStep or WHITE_TEX,
    ABP_MEDIA.textures.striped or WHITE_TEX,
}

-- Saved variable defaults  (all settings are now per-unit-type)
local DEFAULTS = {
    -- Player
    playerZoom  = 75, playerBg = 1, playerBgR = 0.1, playerBgG = 0.1, playerBgB = 0.1, playerBgA = 1.0,
    playerIdle  = false, playerInset = 5, playerX = 0, playerY = 0, playerShape = 1,
    playerBorderC = 2, playerBorderR = 0.86, playerBorderG = 0.90, playerBorderB = 0.95, playerBorderSize = 2,
    playerBarBC = 2, playerBarBR = 0.86, playerBarBG = 0.90, playerBarBB = 0.95, playerBarBorderSize = 1,
    playerBarLength = 0, playerBarHeight = 0,
    playerBarTexture = 1,
    playerBarGloss = true,
    playerBarShine = false, playerBarShadow = false, playerBarGlow = false,
    playerHealthColorMode = 1, playerHealthR = 0.0, playerHealthG = 0.85, playerHealthB = 0.15,
    playerHealthER = 0.0, playerHealthEG = 0.45, playerHealthEB = 0.0,
    playerHealthUseClassColor = false,
    playerResourceColorMode = 1, playerResourceR = 0.0, playerResourceG = 0.55, playerResourceB = 1.0,
    playerResourceER = 0.0, playerResourceEG = 0.25, playerResourceEB = 0.85,
    playerResourceUseClassColor = false,
    playerNameHighlightMode = 1, playerNameHighlightR = 0.0, playerNameHighlightG = 0.0, playerNameHighlightB = 0.0, playerNameHighlightA = 0.45,
    playerNameTextMode = 1, playerNameTextR = 0.86, playerNameTextG = 0.90, playerNameTextB = 0.95,
    playerClassPowerEnabled = true,
    playerClassPowerSize = 18,
    playerClassPowerSpacing = 4,
    playerClassPowerBorderSize = 1,
    playerClassPowerShape = 1,
    playerClassPowerXOffset = 0,
    playerClassPowerYOffset = -6,
    playerClassPowerHideBlizzard = false,
    playerUseCustomRunes = true,
    playerRuneTimerText = true,
    playerRuneCooldownShade = 38,
    playerRuneStyle = 1,
    playerComboPointStyle = 1,
    -- Target
    targetZoom  = 75, targetBg = 1, targetBgR = 0.1, targetBgG = 0.1, targetBgB = 0.1, targetBgA = 1.0,
    targetIdle  = false, targetInset = 5, targetX = 0, targetY = 0, targetShape = 1,
    targetBorderC = 2, targetBorderR = 0.86, targetBorderG = 0.90, targetBorderB = 0.95, targetBorderSize = 2,
    targetBarBC = 2, targetBarBR = 0.86, targetBarBG = 0.90, targetBarBB = 0.95, targetBarBorderSize = 1,
    targetBarLength = 0, targetBarHeight = 0,
    targetBarTexture = 1,
    targetBarGloss = true,
    targetBarShine = false, targetBarShadow = false, targetBarGlow = false,
    targetHealthColorMode = 1, targetHealthR = 0.0, targetHealthG = 0.85, targetHealthB = 0.15,
    targetHealthER = 0.0, targetHealthEG = 0.45, targetHealthEB = 0.0,
    targetHealthUseClassColor = false,
    targetResourceColorMode = 1, targetResourceR = 0.0, targetResourceG = 0.55, targetResourceB = 1.0,
    targetResourceER = 0.0, targetResourceEG = 0.25, targetResourceEB = 0.85,
    targetResourceUseClassColor = false,
    targetNameHighlightMode = 1, targetNameHighlightR = 0.0, targetNameHighlightG = 0.0, targetNameHighlightB = 0.0, targetNameHighlightA = 0.45,
    targetNameTextMode = 1, targetNameTextR = 0.86, targetNameTextG = 0.90, targetNameTextB = 0.95,
    -- Focus
    focusZoom   = 75, focusBg  = 1, focusBgR  = 0.1, focusBgG  = 0.1, focusBgB  = 0.1, focusBgA  = 1.0,
    focusIdle   = false, focusInset  = 5, focusX  = 0, focusY  = 0, focusShape  = 1,
    focusBorderC  = 2, focusBorderR  = 0.86, focusBorderG  = 0.90, focusBorderB  = 0.95, focusBorderSize = 2,
    focusBarBC = 2, focusBarBR = 0.86, focusBarBG = 0.90, focusBarBB = 0.95, focusBarBorderSize = 1,
    focusBarLength = 0, focusBarHeight = 0,
    focusBarTexture = 1,
    focusBarGloss = true,
    focusBarShine = false, focusBarShadow = false, focusBarGlow = false,
    focusHealthColorMode = 1, focusHealthR = 0.0, focusHealthG = 0.85, focusHealthB = 0.15,
    focusHealthER = 0.0, focusHealthEG = 0.45, focusHealthEB = 0.0,
    focusHealthUseClassColor = false,
    focusResourceColorMode = 1, focusResourceR = 0.0, focusResourceG = 0.55, focusResourceB = 1.0,
    focusResourceER = 0.0, focusResourceEG = 0.25, focusResourceEB = 0.85,
    focusResourceUseClassColor = false,
    focusNameHighlightMode = 1, focusNameHighlightR = 0.0, focusNameHighlightG = 0.0, focusNameHighlightB = 0.0, focusNameHighlightA = 0.45,
    focusNameTextMode = 1, focusNameTextR = 0.86, focusNameTextG = 0.90, focusNameTextB = 0.95,
    -- Party
    partyZoom   = 75, partyBg  = 1, partyBgR  = 0.1, partyBgG  = 0.1, partyBgB  = 0.1, partyBgA  = 1.0,
    partyIdle   = false, partyInset  = 5, partyX  = 0, partyY  = 0, partyShape  = 1,
    partyBorderC  = 2, partyBorderR  = 0.86, partyBorderG  = 0.90, partyBorderB  = 0.95, partyBorderSize = 2,
    partyBarBC = 2, partyBarBR = 0.86, partyBarBG = 0.90, partyBarBB = 0.95, partyBarBorderSize = 1,
    partyBarLength = 0, partyBarHeight = 0,
    partyBarTexture = 1,
    partyBarGloss = true,
    partyBarShine = false, partyBarShadow = false, partyBarGlow = false,
    partyHealthColorMode = 1, partyHealthR = 0.0, partyHealthG = 0.85, partyHealthB = 0.15,
    partyHealthER = 0.0, partyHealthEG = 0.45, partyHealthEB = 0.0,
    partyHealthUseClassColor = false,
    partyResourceColorMode = 1, partyResourceR = 0.0, partyResourceG = 0.55, partyResourceB = 1.0,
    partyResourceER = 0.0, partyResourceEG = 0.25, partyResourceEB = 0.85,
    partyResourceUseClassColor = false,
    partyNameHighlightMode = 1, partyNameHighlightR = 0.0, partyNameHighlightG = 0.0, partyNameHighlightB = 0.0, partyNameHighlightA = 0.45,
    partyNameTextMode = 1, partyNameTextR = 0.86, partyNameTextG = 0.90, partyNameTextB = 0.95,
    -- Pet
    petZoom   = 75, petBg  = 1, petBgR  = 0.1, petBgG  = 0.1, petBgB  = 0.1, petBgA  = 1.0,
    petIdle   = false, petInset  = 5, petX  = 0, petY  = 0, petShape  = 1,
    petBorderC  = 2, petBorderR  = 0.86, petBorderG  = 0.90, petBorderB  = 0.95, petBorderSize = 2,
    petBarBC = 2, petBarBR = 0.86, petBarBG = 0.90, petBarBB = 0.95, petBarBorderSize = 1,
    petBarLength = 0, petBarHeight = 0,
    petBarTexture = 1,
    petBarGloss = true,
    petBarShine = false, petBarShadow = false, petBarGlow = false,
    petHealthColorMode = 1, petHealthR = 0.0, petHealthG = 0.85, petHealthB = 0.15,
    petHealthER = 0.0, petHealthEG = 0.45, petHealthEB = 0.0,
    petHealthUseClassColor = false,
    petResourceColorMode = 1, petResourceR = 0.0, petResourceG = 0.55, petResourceB = 1.0,
    petResourceER = 0.0, petResourceEG = 0.25, petResourceEB = 0.85,
    petResourceUseClassColor = false,
    petNameHighlightMode = 1, petNameHighlightR = 0.0, petNameHighlightG = 0.0, petNameHighlightB = 0.0, petNameHighlightA = 0.45,
    petNameTextMode = 1, petNameTextR = 0.86, petNameTextG = 0.90, petNameTextB = 0.95,
    -- Hide PvP / prestige emblems
    playerHideEmblem = false,
    targetHideEmblem = false,
    focusHideEmblem  = false,
    partyHideEmblem  = false,
    petHideEmblem    = false,
    -- Hide only the rested ZZZ indicator; the ring has its own toggle
    playerHideRested = false,
    -- Suppress the native pulsing status ring independently of rested icons.
    playerHideStatusGlow = false,
    -- Hide the small player portrait icons (role icon + lower-right corner)
    playerHideRoleIcon = false,
    -- Raise combat-feedback numbers (hit/heal/absorb) above the player portrait
    playerShowCombatText = true,
    -- Profiles: { [name] = { copy of all setting keys } }
    profiles = {},
    settingsAppearance = "default", -- Settings-window skin; included in saved profiles.
    -- Migration flags (set to true after one-time data fixes are applied)
    borderOrderMigrated = false,
    barBorderOrderMigrated = false,
    designVersion = 2,
}

-------------------------------------------------------------------------------
-- Event / update frame
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame.timer = 0
eventFrame:RegisterEvent("PLAYER_LOGIN")

function ABP:StartBarColorBurst(duration)
    local now = GetTime and GetTime() or 0
    self.barColorBurstUntil = math.max(self.barColorBurstUntil or 0, now + (duration or 0.18))
end

local classicFlashSuppressed = {}
local classicFlashTextures = {}

local nativeTextureAlpha = setmetatable({}, { __mode = "k" })
local function SetNativeTextureHidden(texture, hide)
    if not (texture and texture.SetAlpha) then return end
    if hide then
        if nativeTextureAlpha[texture] == nil then
            local alpha = 1
            if texture.GetAlpha then alpha = texture:GetAlpha() end
            if issecretvalue and issecretvalue(alpha) then alpha = 1 end
            if type(alpha) ~= "number" then alpha = 1 end
            nativeTextureAlpha[texture] = alpha
        end
        texture:SetAlpha(0)
    elseif nativeTextureAlpha[texture] ~= nil then
        texture:SetAlpha(nativeTextureAlpha[texture])
        nativeTextureAlpha[texture] = nil
    end
end

-- Keep suppression separate from all native color/opacity writes. A fully
-- transparent owned mask clips the status artwork without changing its shown
-- state, scripts, RGB or pulsing alpha. Remove only our mask when disabled.
local nativeStatusMasks = setmetatable({}, { __mode = "k" })
local function SetNativeStatusGlowHidden(texture, hide)
    if not texture then return end
    local state = nativeStatusMasks[texture]
    if hide then
        if not (texture.AddMaskTexture and texture.GetParent) then return end
        if not state then
            local parent = texture:GetParent()
            if not (parent and parent.CreateMaskTexture) then return end
            local mask = parent:CreateMaskTexture()
            mask:SetAllPoints(texture)
            mask:SetTexture("Interface\\AddOns\\AnimatedBlizzPortrait\\media\\transparent-mask.tga",
                "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            state = {mask = mask, attached = false}
            nativeStatusMasks[texture] = state
        end
        if not state.attached then
            texture:AddMaskTexture(state.mask)
            state.attached = true
        end
    elseif state and state.attached then
        texture:RemoveMaskTexture(state.mask)
        state.attached = false
    end
end

local function ReadableTextureText(value)
    -- Retail can return secret atlas/texture identifiers during combat.
    -- Check before indexing, converting, or inspecting the value.
    if issecretvalue and issecretvalue(value) then return "" end
    if type(value) == "string" then return string.lower(value) end
    if type(value) == "number" then return tostring(value) end
    return ""
end

local function SafeRegionValue(region, getter)
    if not (region and getter) then return nil end
    if region.IsForbidden and region:IsForbidden() then return nil end
    local ok, value = pcall(getter, region)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end

local function IsClassicFrameFlashTexture(region)
    if not region or not region.GetObjectType or region:GetObjectType() ~= "Texture" then return false end

    local name, atlas, texture = "", "", ""
    if region.GetName then name = ReadableTextureText(region:GetName()) end
    if region.GetAtlas then atlas = ReadableTextureText(region:GetAtlas()) end
    if region.GetTexture then texture = ReadableTextureText(region:GetTexture()) end
    local text = name .. " " .. atlas .. " " .. texture

    if text:find("health", 1, true)
        or text:find("mana", 1, true)
        or text:find("power", 1, true)
        or text:find("resource", 1, true)
        or text:find("statusbar", 1, true)
        or text:find("namebackground", 1, true)
        or text:find("namebg", 1, true) then
        return false
    end

    return text:find("flash", 1, true)
        or text:find("damage", 1, true)
        or text:find("heal", 1, true)
        or text:find("hitindicator", 1, true)
        or text:find("combatfeedback", 1, true)
        or text:find("portraiton%-status")
end

local function SuppressClassicFrameFlashTexture(region)
    if not region then return end
    if region.SetAlpha then region:SetAlpha(0) end
    if region.SetVertexColor then region:SetVertexColor(1, 1, 1, 0) end
    if region.Hide then region:Hide() end

    if classicFlashSuppressed[region] then return end
    classicFlashSuppressed[region] = true
    classicFlashTextures[#classicFlashTextures + 1] = region
    if not region.HookScript then return end
    pcall(region.HookScript, region, "OnShow", function(s)
        if s.SetAlpha then s:SetAlpha(0) end
        if s.SetVertexColor then s:SetVertexColor(1, 1, 1, 0) end
        if s.Hide then s:Hide() end
    end)
end

local function ScanClassicFlashFrame(frame, depth, seen)
    if not frame or depth < 0 or seen[frame] then return end
    seen[frame] = true

    if frame.GetRegions then
        local ok, count = pcall(function() return select("#", frame:GetRegions()) end)
        if ok then
            for i = 1, count do
                local region = select(i, frame:GetRegions())
                if IsClassicFrameFlashTexture(region) then
                    SuppressClassicFrameFlashTexture(region)
                end
            end
        end
    end

    if depth > 0 and frame.GetChildren then
        local ok, count = pcall(function() return select("#", frame:GetChildren()) end)
        if ok then
            for i = 1, count do
                ScanClassicFlashFrame(select(i, frame:GetChildren()), depth - 1, seen)
            end
        end
    end
end

function ABP:FlushClassicFrameFlashTextures()
    if not self.isClassicClient then return end
    for i = #classicFlashTextures, 1, -1 do
        local region = classicFlashTextures[i]
        if region and region.GetObjectType then
            SuppressClassicFrameFlashTexture(region)
        else
            table.remove(classicFlashTextures, i)
        end
    end
end

function ABP:SuppressClassicFrameFlashes()
    if not self.isClassicClient then return end

    self:FlushClassicFrameFlashTextures()

    local seen = {}
    ScanClassicFlashFrame(PlayerFrame, 2, seen)
    ScanClassicFlashFrame(PetFrame, 2, seen)
    ScanClassicFlashFrame(TargetFrame, 2, seen)
    ScanClassicFlashFrame(FocusFrame, 2, seen)
    for i = 1, 4 do
        ScanClassicFlashFrame(_G["PartyMemberFrame"..i], 2, seen)
    end

    for _, name in ipairs({
        "PlayerFrameFlash", "PetFrameFlash", "TargetFrameFlash", "FocusFrameFlash",
        "PartyMemberFrame1Flash", "PartyMemberFrame2Flash", "PartyMemberFrame3Flash", "PartyMemberFrame4Flash",
    }) do
        local region = _G[name]
        if IsClassicFrameFlashTexture(region) then
            SuppressClassicFrameFlashTexture(region)
        end
    end
end

eventFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        -- Re-check on some hybrid/fan clients (e.g. "WoW Forever") WOW_PROJECT_MAINLINE
        -- is not yet defined when this file first loads, so isMainlineProject reads
        -- as false at that point. It is always defined by PLAYER_LOGIN.
        local isMainlineProject = WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
        ABP.isModernClient = CLIENT_BUILD >= 120000 or isMainlineProject
        ABP.isClassicClient = CLIENT_BUILD < 40000 and not isMainlineProject
        ABP.supportsCustomFrameOptions = not ABP.isClassicClient
        ABP:Init()
    elseif event == "UNIT_MODEL_CHANGED" then
        for tex, p in pairs(ABP.portraits) do
            if p.unit == unit then ABP:Queue(tex, "low") end
        end
    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_TARGET_CHANGED"
        or event == "PLAYER_FOCUS_CHANGED"
        or event == "GROUP_ROSTER_UPDATE"
        or event == "UNIT_PET" then
        ABP:BootstrapKnownPortraits()
        ABP:RefreshAllBarColors()
        ABP:RefreshAllNameStyles()
        ABP:SuppressClassicFrameFlashes()
        if event == "PLAYER_ENTERING_WORLD" then
            ABP:ReloadAllModels()
            C_Timer.After(1, function() ABP:ReloadAllModels() end)
            C_Timer.After(4, function() ABP:ReloadAllModels() end)
        end
    elseif event == "UNIT_HEALTH"
        or event == "UNIT_HEALTH_FREQUENT"
        or event == "UNIT_MAXHEALTH"
        or event == "UNIT_POWER_UPDATE"
        or event == "UNIT_POWER_FREQUENT"
        or event == "UNIT_MAXPOWER"
        or event == "UNIT_DISPLAYPOWER" then
        ABP:ApplyUnitBarColors(unit)
        ABP:StartBarColorBurst()
        ABP:SuppressClassicFrameFlashes()
        if unit == "player" then
            ABP:RefreshPlayerClassPower()
        end
    elseif event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET"
        or event == "UI_ERROR_MESSAGE" then
        -- A failed action with no target repaints the resource bar to its default
        -- colour without firing a UNIT_POWER event.  Re-clamp the colour now and
        -- start a short per-frame burst so the flash never becomes visible.  Both
        -- paths are resource-bar + colour only, so rapid UI errors stay cheap.
        ABP:BurstReclampBars()
        ABP:StartBarColorBurst(0.3)
    elseif event == "UNIT_NAME_UPDATE" then
        ABP:ApplyUnitNameStyle(unit)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "RUNE_POWER_UPDATE"
        or event == "RUNE_TYPE_UPDATE" then
        ABP:RefreshPlayerClassPower()
    elseif event == "PLAYER_UNGHOST"
        or (event == "UNIT_EXITED_VEHICLE" and unit == "player") then
        if PlayerPortrait and ABP.portraits[PlayerPortrait] then
            C_Timer.After(0.5, function() ABP:Queue(PlayerPortrait, "low") end)
        end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        ABP:RefreshAll()
    end
end)

eventFrame:SetScript("OnUpdate", function(self, elapsed)
    -- Per-frame bar-colour reapply intentionally removed.
    -- It used to call ABP:RefreshVisibleUnitBarColors() every frame for ~0.25s
    -- after each health/power event, which caused the resource and focus bars
    -- to visibly flicker: Blizzard's UnitFrame_Update can swap a bar's
    -- StatusBarTexture handle each tick, which invalidated our overlay cache
    -- and forced ClearAllPoints/SetPoint/Show on the fill overlay 60x/sec.
    -- The 0.25s polling timer below plus the SetStatusBarColor/SetStatusBarTexture
    -- hooks and the UNIT_HEALTH / UNIT_POWER events are sufficient to keep
    -- the custom colours current.
    ABP:FlushClassicFrameFlashTextures()

    -- Short post-action burst: re-clamp the custom resource colour every frame for
    -- ~0.3s after a spell fails / "There is nothing to attack".  With a target the
    -- frequent UNIT_POWER events already keep the colour current; with no target no
    -- power event fires, so without this the bar flashes its default colour until
    -- the 0.25s tick below.  Colour-only (no overlay rebuild) so it cannot flicker.
    if (ABP.barColorBurstUntil or 0) > GetTime() then
        ABP:BurstReclampBars()
    end

    ABP.barColorTick = (ABP.barColorTick or 0) + elapsed
    if ABP.barColorTick >= 0.25 then
        ABP.barColorTick = 0
        ABP:RefreshVisibleUnitBarColors()
        ABP:RefreshVisibleUnitNameStyles()
        ABP:SuppressClassicFrameFlashes()
        ABP:RefreshNativeIconVisibility()
    end
    ABP.classPowerTimerTick = (ABP.classPowerTimerTick or 0) + elapsed
    if ABP.classPowerTimerTick >= 0.05 then
        ABP.classPowerTimerTick = 0
        ABP:UpdatePlayerClassPowerTimerText()
    end
    ABP:DrainRunway(elapsed)
end)

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
function ABP:Init()
    if not AnimatedBlizzPortraitDB then
        AnimatedBlizzPortraitDB = CopyTable(DEFAULTS)
        -- New databases already use the current option order. Legacy migrations
        -- must not turn the new Transparent defaults into opaque Slate borders.
        AnimatedBlizzPortraitDB.borderOrderMigrated = true
        AnimatedBlizzPortraitDB.barBorderOrderMigrated = true
    else
        if AnimatedBlizzPortraitDB.playerHideStatusGlow == nil then
            AnimatedBlizzPortraitDB.playerHideStatusGlow = AnimatedBlizzPortraitDB.playerHideRested or false
        end
        for k, v in pairs(DEFAULTS) do
            if AnimatedBlizzPortraitDB[k] == nil then
                AnimatedBlizzPortraitDB[k] = v
            end
        end
    end
    self.db = AnimatedBlizzPortraitDB

    if self.isClassicClient then
        for _, pre in ipairs({ "player", "target", "focus", "party", "pet" }) do
            self.db[pre.."Idle"] = true
            self.db[pre.."HideEmblem"] = false
        end
        self.db.playerHideRested = false
        self.db.playerHideRoleIcon = false
        if not self.db.classicPlayerHealthClassColorMigrated then
            if self.db.playerHealthColorMode == 4 then
                self.db.playerHealthColorMode = 1
            end
            self.db.classicPlayerHealthClassColorMigrated = true
        end
    end

    -- One-time migration: BorderC order changed from (legacy Gold=1,Silver=2,Transparent=3,Class=4,Custom=5)
    -- to (Transparent=1,Steel=2,Silver=3,Class=4,Custom=5).  Guard with a flag so it never re-runs.
    if not self.db.borderOrderMigrated then
        local borderMigrate = { [1]=2, [2]=3, [3]=1 }
        for _, pre in ipairs({"player","target","focus","party","pet"}) do
            local key = pre.."BorderC"
            local old = self.db[key]
            if borderMigrate[old] then self.db[key] = borderMigrate[old] end
        end
        self.db.borderOrderMigrated = true
    end

    -- One-time migration: BarBorderC order swapped so Steel=2, Silver=3 (matches BorderC symmetry).
    -- Old layout was Silver=2, legacy Gold=3.  Swap existing saved values 2↔3.
    if not self.db.barBorderOrderMigrated then
        for _, pre in ipairs({"player","target","focus","party","pet"}) do
            local key = pre.."BarBC"
            local old = self.db[key]
            if     old == 2 then self.db[key] = 3
            elseif old == 3 then self.db[key] = 2 end
        end
        self.db.barBorderOrderMigrated = true
    end

    if (self.db.designVersion or 0) < 2 then
        for _, pre in ipairs({"player","target","focus","party","pet"}) do
            local borderKey = pre .. "BorderC"
            if self.db[borderKey] == 3 or self.db[borderKey] == 4 then
                self.db[borderKey] = 2
            end

            local barBorderKey = pre .. "BarBC"
            if self.db[barBorderKey] == 1 or self.db[barBorderKey] == 2 or self.db[barBorderKey] == 3 then
                self.db[barBorderKey] = 2
            end

            local colorMigrations = {
                { key = pre .. "BorderR", old = 0.82, new = 0.86 },
                { key = pre .. "BorderG", old = 0.85, new = 0.90 },
                { key = pre .. "BorderB", old = 0.90, new = 0.95 },
                { key = pre .. "BarBR", old = 0.82, new = 0.86 },
                { key = pre .. "BarBG", old = 0.85, new = 0.90 },
                { key = pre .. "BarBB", old = 0.90, new = 0.95 },
                { key = pre .. "NameTextR", old = 0.82, new = 0.86 },
                { key = pre .. "NameTextG", old = 0.85, new = 0.90 },
                { key = pre .. "NameTextB", old = 0.90, new = 0.95 },
            }
            for _, rule in ipairs(colorMigrations) do
                if self.db[rule.key] == rule.old then
                    self.db[rule.key] = rule.new
                end
            end
        end
        self.db.designVersion = 2
    end

    -- Defer the entire callback to the next frame.
    --
    -- In WoW Midnight, hooksecurefunc callbacks fire synchronously inside the
    -- protected call chain that invoked the hooked function.  When
    -- SetPortraitTexture is called from PlayerFrame_ToPlayerArt (triggered by
    -- PLAYER_AURAS_CHANGED / UNIT_PORTRAIT_UPDATE), Midnight's secure executor
    -- is actively holding aura timing fields (expirationTime, duration, etc.)
    -- as "secret" numbers.  Any API reads we make in that same execution context
    -- (UnitGUID, texture:GetPoint, GetCenter, etc.) cause the taint to escape
    -- into global state, which then makes BuffFrame:UpdatePlayerBuffs crash with
    -- "attempt to perform arithmetic on a secret number value".
    --
    -- C_Timer.After(0, ...) schedules the work for the very next frame, after
    -- the protected chain finishes and the secret-value scope has closed.
    -- The 1-frame delay is imperceptible because portrait model loading already
    -- takes several frames.
    hooksecurefunc("SetPortraitTexture", function(texture, unit)
        C_Timer.After(0, function()
            ABP:OnSetPortraitTexture(texture, unit)
        end)
    end)
    C_Timer.After(0, function() ABP:BootstrapKnownPortraits() end)
    C_Timer.After(0.5, function() ABP:BootstrapKnownPortraits() end)
    C_Timer.After(1, function() ABP:SuppressClassicFrameFlashes() end)

    ---------------------------------------------------------------------------
    -- Bar colour strategy (TWW / Midnight)
    --
    -- bar.lockColor is intentionally NOT used: Blizzard reads it inside the
    -- secure SetValue chain, causing "secret number" taint crashes.
    --
    -- Instead we rely on two mechanisms:
    --   1. UNIT_HEALTH / UNIT_POWER_UPDATE event handlers call
    --      ABP:ApplyUnitBarColors(unit).  Addon OnEvent handlers fire AFTER
    --      Blizzard's securecall chain, so our SetStatusBarColor runs last.
    --   2. hooksecurefunc("UnitFrameHealthBar_Update") + C_Timer.After(0)
    --      catches per-frame resets from PlayerFrame_OnUpdate without entering
    --      the secure chain (same safe deferral pattern as SetPortraitTexture).
    -- The 0.25 s OnUpdate timer is an additional fallback.
    ---------------------------------------------------------------------------

    -- Re-apply bar colours after Blizzard health updates reset them.  On retail
    -- this also keeps us outside the secure SetValue chain; on TBC it prevents
    -- the player health bar from being left with the raw white status texture.
    local function RefreshAfterClassicBarUpdate()
        if ABP.isClassicClient and ABP.db then
            ABP:RefreshVisibleUnitBarColors()
            ABP:StartBarColorBurst(0.25)
            ABP:SuppressClassicFrameFlashes()
        end
    end

    if UnitFrameHealthBar_Update then
        hooksecurefunc("UnitFrameHealthBar_Update", function()
            if ABP.isClassicClient then
                RefreshAfterClassicBarUpdate()
            else
                C_Timer.After(0, function()
                    if ABP.db then
                        ABP:RefreshVisibleUnitBarColors()
                        ABP:StartBarColorBurst()
                    end
                end)
            end
        end)
    end
    for _, fnName in ipairs({ "UnitFrameManaBar_Update", "UnitFramePowerBar_Update", "UnitFrame_Update" }) do
        if _G[fnName] and hooksecurefunc then
            pcall(hooksecurefunc, fnName, RefreshAfterClassicBarUpdate)
        end
    end
    -- High-frequency SetValue hooks intentionally omitted (previously included
    -- UnitFrameHealthBar_OnValueChanged, TargetFrameHealthBar_OnValueChanged,
    -- TextStatusBar_OnValueChanged, TextStatusBar_UpdateTextString, etc.).
    -- TBC's TextStatusBar animates value changes by calling SetValue every
    -- frame for ~0.5s, so these hooks fired dozens of times per health/mana
    -- change.  Each fire re-applied the bar colour, and any transient dedup
    -- miss became a visible flicker on the target/focus bars during the
    -- smooth-bar animation.  We keep only the hooks below, which fire on
    -- semantic state changes (faction/dead/power-type), not every SetValue.
    for _, fnName in ipairs({
        "UnitFrameManaBar_UpdateType",
        "TargetFrame_CheckDead",
        "TargetFrame_CheckFaction",
        "PetFrame_Update",
    }) do
        if _G[fnName] and hooksecurefunc then
            pcall(hooksecurefunc, fnName, function()
                if ABP.isClassicClient then
                    RefreshAfterClassicBarUpdate()
                end
            end)
        end
    end

    if not self.isClassicClient then
        -- Rested glow suppression.
        -- Hook Blizzard's own show/hide functions so our setting sticks whenever
        -- the player enters/leaves a rested area (PLAYER_UPDATE_RESTING event).
        C_Timer.After(1, function()
            ABP:FlushRestedHide()

        -- Hook ZZZ animation updater.
        -- Wrapped in C_Timer.After(0) so it never fires synchronously inside
        -- Midnight's protected aura-update chain (which would taint expirationTime).
        if PlayerFrame_UpdatePlayerRestLoop then
            hooksecurefunc("PlayerFrame_UpdatePlayerRestLoop", function()
                C_Timer.After(0, function()
                    if ABP.db and ABP.db.playerHideRested then
                        local restLoop = PlayerFrame
                            and PlayerFrame.PlayerFrameContent
                            and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual
                            and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerRestLoop
                        if restLoop then
                            restLoop:Hide()
                            if restLoop.PlayerRestLoopAnim then restLoop.PlayerRestLoopAnim:Stop() end
                        end
                    end
                end)
            end)
        end

        -- Reapply alpha after Blizzard's status updater, without texture scripts
        -- or replacing Blizzard's Show/SetShown methods.
            if PlayerFrame_UpdateStatus then
                hooksecurefunc("PlayerFrame_UpdateStatus", function()
                    C_Timer.After(0, function()
                        ABP:FlushStatusGlowHide()
                    end)
                end)
            end
        end)
    end

    eventFrame:RegisterEvent("UNIT_MODEL_CHANGED")
    eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("UNIT_PET")
    eventFrame:RegisterUnitEvent("UNIT_HEALTH", "player", "pet", "target", "focus", "party1", "party2", "party3", "party4")
    pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_HEALTH_FREQUENT", "player", "pet", "target", "focus", "party1", "party2", "party3", "party4")
    eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player", "pet", "target", "focus", "party1", "party2", "party3", "party4")
    eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player", "pet", "target", "focus", "party1", "party2", "party3", "party4")
    eventFrame:RegisterUnitEvent("UNIT_NAME_UPDATE", "player", "pet", "target", "focus", "party1", "party2", "party3", "party4")
    eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player", "pet", "target", "focus", "party1", "party2", "party3", "party4")
    eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player", "pet", "target", "focus", "party1", "party2", "party3", "party4")
    eventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player", "pet", "target", "focus", "party1", "party2", "party3", "party4")
    -- Failed-action repaints (e.g. "There is nothing to attack") fire no UNIT_POWER
    -- event, so catch the failure directly to re-clamp the custom resource colour.
    pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_SPELLCAST_FAILED", "player")
    pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_SPELLCAST_FAILED_QUIET", "player")
    pcall(eventFrame.RegisterEvent, eventFrame, "UI_ERROR_MESSAGE")
    eventFrame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    eventFrame:RegisterEvent("RUNE_POWER_UPDATE")
    eventFrame:RegisterEvent("RUNE_TYPE_UPDATE")
    eventFrame:RegisterEvent("UI_SCALE_CHANGED")
    eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    eventFrame:RegisterEvent("PLAYER_UNGHOST")
    C_Timer.After(1, function()
        ABP:RefreshAllBarColors()
        ABP:RefreshAllNameStyles()
    end)

    if not self.isClassicClient then
        -- PvP / prestige emblems are textures (PVPIcon, PrestigePortrait, PrestigeBadge)
        -- inside PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.
        -- Because they are textures we raise the parent frame's local frame level
        -- so they render above the portrait model and steel border without escaping
        -- the unit-frame layer and covering bags, the map, or menus.
        -- Do not attach scripts to these textures: Blizzard passes secret values
        -- to SetShown in UpdateUnitPvPIndicator, which forbids existing handlers.
        C_Timer.After(1, function()
        -- Exact TWW paths confirmed from Blizzard FrameXML source:
        --   player → PlayerFrameContent.PlayerFrameContentContextual  keys: PVPIcon, PrestigePortrait, PrestigeBadge
        --   target → TargetFrameContent.TargetFrameContentContextual  keys: PvpIcon, PrestigePortrait, PrestigeBadge
        --   focus  → TargetFrameContent.TargetFrameContentContextual  (FocusFrame reuses TargetFrame template)
        --   party  → PartyMemberOverlay                               key:  PVPIcon only
        local function SetupCtx(ctx, pre)
            if not ctx then return end
            if ctx.SetFrameStrata then SetUnitOverlayLayer(ctx) end
            ABP:FlushEmblemHide(pre)
        end

        -- Player
        local pfc = PlayerFrame and PlayerFrame.PlayerFrameContent
        SetupCtx(pfc and pfc.PlayerFrameContentContextual, "player")

        -- Target / Focus both use TargetFrameContent (FocusFrame reuses the TargetFrame template)
        local tfc = TargetFrame and TargetFrame.TargetFrameContent
        SetupCtx(tfc and tfc.TargetFrameContentContextual, "target")

        local ffc = FocusFrame and FocusFrame.TargetFrameContent
        SetupCtx(ffc and ffc.TargetFrameContentContextual, "focus")

        -- Party uses PartyMemberOverlay (no prestige badge, PVPIcon only)
        for i = 1, 4 do
            local uf = _G["PartyMemberFrame"..i]
            SetupCtx(uf and uf.PartyMemberOverlay, "party")
        end

        -- HitIndicator / CombatFeedbackText: raise combat-feedback text above portraits.
        --
        -- Frames (e.g. CombatFeedbackText) that support SetFrameStrata are raised
        -- within MEDIUM. Plain FontStrings (e.g. HitIndicator) get a MEDIUM-strata
        -- mirror that copies text/colour/alpha each frame so the original animation
        -- plays without interference.
        local function WatchHitText(unitRoot, ...)
            local orig = unitRoot
            for i = 1, select("#", ...) do
                orig = orig and orig[select(i, ...)]
            end
            if not orig then return end

            -- Frame: raise it within the unit-frame layer; child FontStrings follow.
            if orig.SetFrameStrata then
                local origStrata = orig:GetFrameStrata()
                SetUnitOverlayLayer(orig)
                return orig, "strata", origStrata
            end

            -- Not a text-capable object — skip.
            if not orig.GetText then return end

            -- Transparent unit-overlay cover sized to the unit-frame root.
            local wrap = CreateFrame("Frame", nil, unitRoot)
            wrap:SetPoint("TOPLEFT",     unitRoot, "TOPLEFT")
            wrap:SetPoint("BOTTOMRIGHT", unitRoot, "BOTTOMRIGHT")
            SetUnitOverlayLayer(wrap)

            -- Mirror FontString: centred on unitRoot, invisible until text fires.
            local mirror = wrap:CreateFontString(nil, "OVERLAY")
            mirror:SetPoint("CENTER", unitRoot, "CENTER", 0, 0)
            mirror:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
            mirror:SetJustifyH("CENTER")
            mirror:SetAlpha(0)

            -- Every frame: sync text, colour, and alpha from original to mirror.
            wrap:SetScript("OnUpdate", function()
                local txt = orig:GetText()
                if txt and txt ~= "" then
                    mirror:SetText(txt)
                    local r, g, b = orig:GetTextColor()
                    if r then mirror:SetTextColor(r, g, b) end
                    mirror:SetAlpha(orig:GetAlpha())
                else
                    mirror:SetAlpha(0)
                end
            end)
            return wrap, "wrap"
        end

        ABP.playerCombatTextItems = {}
        local pci = ABP.playerCombatTextItems
        local function trackPCI(f, k, s) if f then pci[#pci+1] = {frame=f, kind=k, origStrata=s} end end
        trackPCI(WatchHitText(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain", "HitIndicator"))
        trackPCI(WatchHitText(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain", "CombatFeedbackText"))
        WatchHitText(TargetFrame, "TargetFrameContent", "TargetFrameContentMain", "HitIndicator")
        WatchHitText(TargetFrame, "TargetFrameContent", "TargetFrameContentMain", "CombatFeedbackText")
        WatchHitText(FocusFrame,  "TargetFrameContent", "TargetFrameContentMain", "HitIndicator")
        WatchHitText(FocusFrame,  "TargetFrameContent", "TargetFrameContentMain", "CombatFeedbackText")
        for i = 1, 4 do
            local uf = _G["PartyMemberFrame"..i]
            if uf then
                WatchHitText(uf, "HitIndicator")
                WatchHitText(uf, "PartyMemberOverlay", "HitIndicator")
                WatchHitText(uf, "CombatFeedbackText")
            end
        end
        ABP:ApplyPlayerCombatTextSetting()
    end)

    -- Also hook Blizzard's PvP-status updater for immediate hiding on status change.
    -- Wrapped in C_Timer.After(0) to avoid tainting expirationTime in Midnight's
    -- protected aura-update chain (same root cause as the SetPortraitTexture fix above).
    if PlayerFrame_UpdatePvPStatus then
        hooksecurefunc("PlayerFrame_UpdatePvPStatus", function()
            C_Timer.After(0, function()
                ABP:FlushEmblemHide("player")
            end)
        end)
    end

    -- Player role icon (tiny tank/heal/dps icon) lives at:
    -- PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.RoleIcon
    C_Timer.After(1, function()
        -- Role visibility can also be secret; leave this texture script-free.
        ABP:FlushRoleIconHide()
    end)

    if PlayerFrame_UpdateRolesAssigned then
        hooksecurefunc("PlayerFrame_UpdateRolesAssigned", function()
            C_Timer.After(0, function()
                ABP:FlushRoleIconHide()
            end)
        end)
    end

    -- The small lower-right portrait triangle is a separate contextual texture:
    -- PlayerPortraitCornerIcon, shown by PlayerFrame_UpdateStatus().
    C_Timer.After(1, function()
        ABP:FlushCornerIconHide()
    end)

        if PlayerFrame_UpdateStatus then
            hooksecurefunc("PlayerFrame_UpdateStatus", function()
                C_Timer.After(0, function()
                    ABP:FlushCornerIconHide()
                end)
            end)
        end
    end
end

-------------------------------------------------------------------------------
-- Queue
-------------------------------------------------------------------------------
function ABP:Queue(texture, priority)
    if self.runway[texture] == "high" then return end
    self.runway[texture] = priority
    eventFrame.timer = 0
end

function ABP:DrainRunway(elapsed)
    if not next(self.runway) then return end
    for tex, priority in pairs(self.runway) do
        if priority == "high" then
            self:Draw(tex)
            self.runway[tex] = nil
        end
    end
    eventFrame.timer = math.min(eventFrame.timer + elapsed, 0.5)
    if eventFrame.timer >= 0.25 then
        for tex in pairs(self.runway) do self:Draw(tex) end
        wipe(self.runway)
        eventFrame.timer = 0
    end
end

-------------------------------------------------------------------------------
-- Portraits that must never be processed (non-unit-frame contexts)
-------------------------------------------------------------------------------
local EXCLUDED_PORTRAIT_NAMES = {
    CharacterPortrait              = true,   -- character sheet
    InspectPortrait                = true,   -- inspect frame
    GearManagerPortrait            = true,   -- equipment manager
    TalentFramePortrait            = true,   -- talents/PvP panel
    AchievementFrameHeaderPortrait = true,   -- achievements
}

-- Parent frame-name substrings that indicate a non-unit-frame context.
-- Checked up to 5 levels up so deeply nested portraits are caught too.
local EXCLUDED_PARENT_PATTERNS = {
    "Character", "Inspect", "PaperDoll", "GearManager", "Achievement",
    "TalentFrame", "GuildBank", "PlayerSpells", "ReadyCheck",
    "DressUp", "DressingRoom", "Wardrobe",
    "ContainerFrame", "Inventory", "BagBrother", "Baganator",
    -- Dialogs / windows that embed a portrait but are not unit frames:
    "AuctionHouse", "Auction",
    "MailFrame", "OpenMail",
    "GossipFrame", "QuestFrame", "QuestLog",
    "MerchantFrame", "VendorFrame",
    "BankFrame", "Void",
    "ItemUpgrade", "SocketFrame",
    "TradeFrame",
    "CovenantSanctum", "Covenant",
    "ChatConfig", "FloatingChat",
    "LFGDungeonReady", "LFGFrame",
    "Barbershop", "BarberShop",
    "ClassTrial", "Collections",
    "Stable", "PetJournal",
    "Adventure", "Contribution",
    "EncounterJournal",
    "Profession", "CraftingOrder",
}

local function IsExcludedPortrait(texture)
    local name = SafeRegionValue(texture, texture.GetName) or ""
    if EXCLUDED_PORTRAIT_NAMES[name] then return true end
    local parent = texture:GetParent()
    for _ = 1, 5 do   -- check up to 5 levels up to catch deeply nested portraits
        if not parent then break end
        local pn = SafeRegionValue(parent, parent.GetName) or ""
        for _, pat in ipairs(EXCLUDED_PARENT_PATTERNS) do
            if pn:find(pat) then return true end
        end
        parent = parent:GetParent()
    end
    return false
end

local function ReleaseExcludedPortrait(texture)
    local p = ABP.portraits[texture]
    if not p then return end

    texture:Show()
    if p.model then p.model:Hide() end
    if p.staticPortrait then p.staticPortrait:Hide() end
    if p.back then p.back:Hide() end
    if p.backSq then p.backSq:Hide() end
    if p.borderT then p.borderT:Hide() end
    if p.borderB then p.borderB:Hide() end
    if p.borderL then p.borderL:Hide() end
    if p.borderR then p.borderR:Hide() end
    if p.ringOverlay then p.ringOverlay:Hide() end
    if p.ringFrame then p.ringFrame:Hide() end
    if p.sqFrame then p.sqFrame:Hide() end
    if p.classPowerFrame then p.classPowerFrame:Hide() end
    for _, r in ipairs(p.blizzRings or {}) do
        r:SetVertexColor(1, 1, 1, 1)
    end
    ABP.portraits[texture] = nil
end

-------------------------------------------------------------------------------
-- Hook callback
-------------------------------------------------------------------------------
function ABP:OnSetPortraitTexture(texture, unit)
    if not UnitExists(unit) then return end
    if texture.noABP then return end
    if IsExcludedPortrait(texture) then
        ReleaseExcludedPortrait(texture)
        return
    end

    local p = self.portraits[texture]
    if not p then
        p = self:CreatePortrait(texture, unit)
        self:Draw(texture)
    elseif p.unit ~= unit then
        p.unit = unit
        p.guid = nil
        self:Queue(texture, "high")
    end

    local guid = UnitGUID(unit)
    if self.isModernClient
        and type(issecretvalue) == "function"
        and issecretvalue(guid)
    then
        self:Queue(texture, "high")
        p.guid = nil
        return
    end
    if guid ~= p.guid then self:Queue(texture, "high") end
    p.guid = guid
end

function ABP:BootstrapKnownPortraits()
    local known = {
        { PlayerPortrait, "player" },
        { PetPortrait, "pet" },
        { TargetFramePortrait, "target" },
        { FocusFramePortrait, "focus" },
    }
    for i = 1, 4 do
        known[#known + 1] = { _G["PartyMemberFrame"..i.."Portrait"], "party"..i }
    end

    for _, entry in ipairs(known) do
        local texture, unit = entry[1], entry[2]
        if texture and UnitExists(unit) then
            self:OnSetPortraitTexture(texture, unit)
        end
    end
end

-------------------------------------------------------------------------------
-- Portrait construction
-------------------------------------------------------------------------------
function ABP:CreatePortrait(texture, unit)
    local p = { unit = unit }
    self.portraits[texture] = p

    p.cx = texture:GetWidth()
    p.cy = texture:GetHeight()

    local drawLayer  = texture:GetDrawLayer()
    local modelLayer = (drawLayer == "OVERLAY") and "ARTWORK" or "BACKGROUND"
    local parent     = texture:GetParent()

    -- Helper: copy anchor points from a texture, skipping any that carry secret
    -- (tainted) offset values.  In Midnight, GetPoint() can return secret numbers
    -- if the texture belongs to a frame that was last touched inside a protected
    -- execution scope.  Passing secret values to SetPoint would re-introduce taint.
    local _isec = type(issecretvalue) == "function" and issecretvalue or nil
    local function CopyPoints(dst, src)
        for i = 1, src:GetNumPoints() do
            local pt, relTo, relPt, xOff, yOff = src:GetPoint(i)
            if _isec and (_isec(xOff) or _isec(yOff)) then
                -- Secret offsets: anchor to the same relative frame but zero offsets.
                -- The model will snap to its correct position on the next full Draw().
                dst:SetPoint(pt, relTo, relPt, 0, 0)
            else
                dst:SetPoint(pt, relTo, relPt, xOff, yOff)
            end
        end
    end

    -- Invisible anchor (layout reference)
    p.anchor = CreateFrame("Frame", nil, parent)
    p.anchor:SetWidth(p.cx)
    p.anchor:SetHeight(p.cy)
    CopyPoints(p.anchor, texture)

    -- Clip frame: dynamically tracks the portrait texture via SetAllPoints so it
    -- stays aligned even when Blizzard repositions the texture for unusual mob
    -- geometries (e.g. critters, large beasts) after creation.
    -- SetClipsChildren(true) scissors any child rendering that falls outside,
    -- stopping the 3D model from spilling past the frame edge.
    -- Created BEFORE background textures so they can be parented to it.
    p.clip = CreateFrame("Frame", nil, parent)
    p.clip:SetAllPoints(texture)
    p.clip:SetClipsChildren(true)
    if self.isClassicClient then
        if parent.GetFrameStrata then
            p.clip:SetFrameStrata(parent:GetFrameStrata())
        end
        if parent.GetFrameLevel then
            p.clip:SetFrameLevel(math.max(0, parent:GetFrameLevel() - 1))
        end
    else
        -- Stay in MEDIUM strata so ordinary Blizzard windows can cover the
        -- portrait.  A local frame-level bump keeps it above the unit-frame bars.
        p.clip:SetFrameStrata(UNIT_ART_STRATA)
        if parent.GetFrameLevel then
            p.clip:SetFrameLevel(parent:GetFrameLevel() + UNIT_ART_LEVEL_OFFSET)
        end
    end

    -- Background texture (circular via AddMaskTexture).
    -- Parented to p.clip at BACKGROUND draw layer so the render order is:
    --   mana/resource bar (MEDIUM strata, lower frame level)
    --   → background (p.clip MEDIUM strata, BACKGROUND layer — before child frames)
    --   → avatar model (child frame of p.clip — renders after parent BACKGROUND)
    --   → border (p.clip MEDIUM strata, OVERLAY layer — renders after child frames)
    p.back = p.clip:CreateTexture(nil, "BACKGROUND", nil, -1)
    p.back:Hide()
    p.back:SetAllPoints(p.clip)
    local backMask = p.clip:CreateMaskTexture()
    backMask:SetAllPoints(p.back)
    backMask:SetTexture("Interface\\Masks\\CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    p.back:AddMaskTexture(backMask)

    -- Square background texture (no mask — shown when shape = 2)
    p.backSq = p.clip:CreateTexture(nil, "BACKGROUND", nil, -1)
    p.backSq:Hide()
    p.backSq:SetAllPoints(p.clip)

    -- 3D model (parented to clip so it gets scissored at the border edge).
    -- Do NOT call SetFrameStrata on the model — doing so detaches it from p.clip's
    -- rendering context and breaks SetClipsChildren.  The model inherits MEDIUM from
    -- p.clip automatically.
    p.model = CreateFrame("PlayerModel", nil, p.clip, "ABPModelTemplate")
    p.model:Hide()
    p.model.parentTexture = texture
    p.model:SetModelDrawLayer(modelLayer)

    -- Model data streams in asynchronously, which is most noticeable right after
    -- zoning into a dungeon or raid where a large batch of creature models loads
    -- at once.  OnModelLoaded fires once the data is actually available; queue a
    -- redraw then so the portrait swaps from the 2D fallback to the live model.
    -- Guarded on p.modelLoaded so a re-fire for a model we already consider
    -- loaded cannot bounce Draw → SetUnit → OnModelLoaded → Draw forever.
    -- pcall'd because SetScript errors on handlers the client does not know, and
    -- ABP also ships TOCs for the older Classic flavours (same defensive pattern
    -- as the pcall'd RegisterUnitEvent calls in Init).  The retry ladder in
    -- ApplyUnitModel covers loading on its own if this handler is unavailable.
    pcall(p.model.SetScript, p.model, "OnModelLoaded", function(m)
        local pp = ABP.portraits[m.parentTexture]
        if not pp or pp.modelLoaded then return end
        pp.modelLoaded = true
        pp.modelRetry  = 0
        ABP:Queue(m.parentTexture, "high")
    end)

    self:PositionModel(p, unit)

    -- Square steel border: 4 edge textures on p.clip (MEDIUM strata, OVERLAY layer)
    -- so they render above both the 3D model and Blizzard's mana/health bars.
    local BW = 2
    local function MakeBorderEdge()
        local e = p.clip:CreateTexture(nil, "OVERLAY", nil, 3)
        e:SetColorTexture(0.22, 0.31, 0.40, 1)
        e:Hide()
        return e
    end
    p.borderT = MakeBorderEdge()
    p.borderT:SetPoint("TOPLEFT",  p.clip, "TOPLEFT",  0, 0)
    p.borderT:SetPoint("TOPRIGHT", p.clip, "TOPRIGHT", 0, 0)
    p.borderT:SetHeight(BW)

    p.borderB = MakeBorderEdge()
    p.borderB:SetPoint("BOTTOMLEFT",  p.clip, "BOTTOMLEFT",  0, 0)
    p.borderB:SetPoint("BOTTOMRIGHT", p.clip, "BOTTOMRIGHT", 0, 0)
    p.borderB:SetHeight(BW)

    p.borderL = MakeBorderEdge()
    p.borderL:SetPoint("TOPLEFT",    p.clip, "TOPLEFT",    0, 0)
    p.borderL:SetPoint("BOTTOMLEFT", p.clip, "BOTTOMLEFT", 0, 0)
    p.borderL:SetWidth(BW)

    p.borderR = MakeBorderEdge()
    p.borderR:SetPoint("TOPRIGHT",    p.clip, "TOPRIGHT",    0, 0)
    p.borderR:SetPoint("BOTTOMRIGHT", p.clip, "BOTTOMRIGHT", 0, 0)
    p.borderR:SetWidth(BW)

    -- Circle mode ring border: PortraitOn atlas re-applied at OVERLAY so it renders
    -- above the 3D model.  Parented to p.ringFrame (a sibling of p.clip, NOT a child)
    -- so the full atlas is never scissored by p.clip:SetClipsChildren(true).
    -- Without this the atlas is clipped to the portrait square, producing a visible
    -- partial ring slice instead of the full chrome ring.
    p.ringFrame = CreateFrame("Frame", nil, parent)
    p.ringFrame:SetAllPoints(p.clip)
    p.ringFrame:SetFrameStrata(p.clip:GetFrameStrata())
    p.ringFrame:SetFrameLevel(p.clip:GetFrameLevel() + 10)

    p.ringOverlay = p.ringFrame:CreateTexture(nil, "OVERLAY", nil, 4)
    p.ringOverlay:Hide()
    p.ringOverlay:SetPoint("CENTER", p.clip, "CENTER", 0, 0)
    p.ringOverlay:SetSize(p.cx, p.cy)   -- initial size; updated in Draw

    if not parent.abpTextures then
        parent.abpTextures = {}
        -- Wrapped in C_Timer.After(0): PlayerFrame_ToVehicleArt shows/hides the
        -- unit-frame parent synchronously inside Midnight's protected aura-update
        -- chain.  Running our code synchronously in that context taints
        -- expirationTime, crashing BuffFrame:UpdatePlayerBuffs (same root cause
        -- as the SetPortraitTexture / PvP-emblem fixes above).
        parent:HookScript("OnShow", function(self)
            local s = self
            C_Timer.After(0, function()
                for _, tex in ipairs(s.abpTextures) do ABP:Queue(tex, "high") end
            end)
        end)
        -- When the parent hides (ToT cleared, target switched, etc.) hide ABP
        -- frames so they don't linger.  Deferred for the same taint-isolation
        -- reason as OnShow above.
        parent:HookScript("OnHide", function(self)
            local s = self
            C_Timer.After(0, function()
                for _, tex in ipairs(s.abpTextures) do
                    local pp = ABP.portraits[tex]
                    if pp then
                        pp.model:Hide()
                        if pp.staticPortrait then pp.staticPortrait:Hide() end
                        pp.back:Hide(); pp.backSq:Hide()
                        pp.borderT:Hide(); pp.borderB:Hide()
                        pp.borderL:Hide(); pp.borderR:Hide()
                        if pp.ringOverlay  then pp.ringOverlay:Hide()  end
                        if pp.ringFrame    then pp.ringFrame:Hide()    end
                        if pp.sqFrame      then pp.sqFrame:Hide()      end
                        if pp.classPowerFrame then pp.classPowerFrame:Hide() end
                    end
                end
            end)
        end)
    end
    parent.abpTextures[#parent.abpTextures + 1] = texture

    return p
end

-------------------------------------------------------------------------------
-- Blizzard ring scanner  (runs once per portrait, lazy on first Draw)
-- Uses position + size + draw-layer matching — no atlas required.
-- Scans the portrait's parent regions AND nearby child frames' regions.
-- Anything centered within 50% of portrait width that's portrait-sized and
-- not in BACKGROUND layer is treated as ring chrome.
-------------------------------------------------------------------------------
local function ScanBlizzRings(p, texture)
    -- GetCenter() can return nil when the frame hasn't been positioned yet, or a
    -- secret/tainted value when called on a protected unit-frame texture in Midnight.
    -- Don't cache the result in either case — leave p.blizzRings nil so Draw will
    -- retry on the next call rather than permanently caching an empty table.
    local px, py = texture:GetCenter()
    if not px then return end
    if type(issecretvalue) == "function" and (issecretvalue(px) or issecretvalue(py)) then return end
    p.blizzRings = {}   -- only assigned after we know the texture has a valid position
    local pw = math.max(texture:GetWidth(), texture:GetHeight())

    local ownSet = { [p.back]=true, [p.backSq]=true, [p.clip]=true,
                     [p.model]=true, [p.anchor]=true, [texture]=true,
                     [p.borderT]=true, [p.borderB]=true,
                     [p.borderL]=true, [p.borderR]=true,
                     [p.ringOverlay]=true }

    -- Atlas patterns for portrait ring/chrome textures.
    -- IMPORTANT: bar-fill and embellishment textures (PortraitOn-Bar-Health, -Bar-Mana,
    -- -CornerEmbellishment, etc.) are EXCLUDED.  Blizzard's UnitFrame scripts reset
    -- their vertex colors on every health/mana event, overriding our suppression and
    -- causing coloured lines to bleed over the portrait.  Only the ring-chrome and
    -- decorative overlay textures are included.
    local function IsPortraitAtlas(atlas)
        if not atlas or atlas == "" then return false end
        local low = atlas:lower()
        -- Exclude dynamic/live-updated overlays
        if low:find("%-bar%-")               -- *-Bar-Health, *-Bar-Mana, *-Bar-TempHP…
        or low:find("cornerembellishment")   -- *-CornerEmbellishment
        or low:find("%-status")             -- *-Status (damage flash)
        then return false end
        return low:find("portraiton")        -- UI-HUD-UnitFrame-*-PortraitOn*
            or low:find("portrait%-mask")    -- UI-HUD-UnitFrame-*-Portrait-Mask
            or low:find("portrait%-shadow")  -- UI-HUD-MicroMenu-Portrait-Shadow
            or low:find("micromenu%-portrait")-- UI-HUD-MicroMenu-Portrait-*
    end

    -- issecretvalue is available in Midnight (12.0+) and returns true when a
    -- number is tainted by the secure execution environment.  Secret values are
    -- truthy so a plain nil-check won't catch them, but arithmetic on them throws
    -- "attempt to perform arithmetic on … (a secret number value)" errors.
    local _issecret = type(issecretvalue) == "function" and issecretvalue or nil

    local function CheckRegion(region)
        if ownSet[region] then return end
        if not region.GetCenter then return end
        local regionName = ReadableTextureText(SafeRegionValue(region, region.GetName))
        local regionParent = region.GetParent and region:GetParent() or nil
        local parentName = ReadableTextureText(SafeRegionValue(regionParent, regionParent and regionParent.GetName))
        if regionName:find("health", 1, true)
            or regionName:find("mana", 1, true)
            or regionName:find("power", 1, true)
            or regionName:find("resource", 1, true)
            or regionName:find("statusbar", 1, true)
            or parentName:find("health", 1, true)
            or parentName:find("mana", 1, true)
            or parentName:find("power", 1, true)
            or parentName:find("resource", 1, true)
            or parentName:find("statusbar", 1, true) then
            return
        end
        local rx, ry = region:GetCenter()
        -- Guard 1: nil (frame not yet laid out)
        if not (rx and ry) then return end
        -- Guard 2: secret / tainted values from protected unit-frame regions
        -- (e.g. targettarget, nameplate interiors).  They are truthy so Guard 1
        -- doesn't catch them, but any subsequent arithmetic raises a taint error.
        if _issecret and (_issecret(rx) or _issecret(ry)) then return end

        local atlas = SafeRegionValue(region, region.GetAtlas) or ""

        -- Known portrait atlas names: always include.
        if IsPortraitAtlas(atlas) then
            p.blizzRings[#p.blizzRings + 1] = region
            return
        end

        -- If the region has ANY non-empty atlas name that IsPortraitAtlas rejected
        -- (bars, status, embellishments, etc.), skip it entirely.  Do NOT let it
        -- fall through to the generic position check — Blizzard's UnitFrame scripts
        -- reset vertex color on those textures every combat frame, so suppressing
        -- them via alpha=0 never sticks.
        if atlas ~= "" then return end

        -- Generic fallback for un-atlased textures: non-background, centred near portrait.
        local layer = region.GetDrawLayer and region:GetDrawLayer()
        if layer == "BACKGROUND" then return end
        if ((rx-px)^2 + (ry-py)^2)^0.5 > pw then return end
        p.blizzRings[#p.blizzRings + 1] = region
    end

    local parent  = texture:GetParent()
    local grandpa = parent:GetParent()

    for i = 1, select("#", parent:GetRegions()) do
        CheckRegion(select(i, parent:GetRegions()))
    end

    if grandpa then
        for i = 1, select("#", grandpa:GetRegions()) do
            CheckRegion(select(i, grandpa:GetRegions()))
        end
    end

    -- NOTE: do NOT scan parent:GetChildren() — calling GetRegions() on managed/protected
    -- frames (PetFrame, etc.) from addon code causes security taint that spreads into
    -- Blizzard's secure UnitFrame functions.  Parent + grandparent regions are sufficient
    -- to find PortraitOn and all ring textures.
end

-------------------------------------------------------------------------------
-- Per-unit key prefix helper  (must be defined before PositionModel / Draw)
-------------------------------------------------------------------------------
local function UnitPrefix(unit)
    if unit == "player" then return "player"
    elseif unit == "pet" then return "pet"
    elseif unit == "target" then return "target"
    elseif unit == "focus"  then return "focus"
    elseif unit and unit:sub(1,5) == "party" then return "party"
    end
    return "player"
end

-------------------------------------------------------------------------------
-- Position model (called at create AND every draw so settings take effect live)
-------------------------------------------------------------------------------
function ABP:PositionModel(p, unit)
    local db  = self.db or DEFAULTS
    local pre = UnitPrefix(unit)
    local hs  = db[pre.."X"]     or 0
    local vs  = db[pre.."Y"]     or 0
    local insetVal = db[pre.."Inset"] or 5

    local inset = insetVal / 100
    local xoff  = inset * p.cx
    local yoff  = inset * p.cy

    p.model:ClearAllPoints()
    -- Anchor to p.clip (the model's direct parent) so the child stays inside the
    -- parent's scissor region and SetClipsChildren actually clips it.
    p.model:SetPoint("TOPLEFT",     p.clip, "TOPLEFT",     xoff + hs, -yoff + vs)
    p.model:SetPoint("BOTTOMRIGHT", p.clip, "BOTTOMRIGHT", -xoff + hs,  yoff + vs)
end

-------------------------------------------------------------------------------
-- Background colour
-------------------------------------------------------------------------------
function ABP:ApplyBackground(p, unit)
    if not self.supportsCustomFrameOptions then
        p.back:Hide()
        p.backSq:Hide()
        return
    end

    local db    = self.db
    local pre   = UnitPrefix(unit)
    local bg    = db[pre.."Bg"]    or 1
    local shape = db[pre.."Shape"] or 1  -- 1=Circle, 2=Square

    -- Helper: set colour on the correct back texture and show it
    local function ShowBg(r, g, b, a)
        if shape == 2 then
            p.back:Hide()
            p.backSq:SetColorTexture(r, g, b, a or 1)
            p.backSq:Show()
        else
            p.backSq:Hide()
            p.back:SetColorTexture(r, g, b, a or 1)
            p.back:Show()
        end
    end

    if bg == 1 then
        p.back:Hide()
        p.backSq:Hide()
    elseif bg == 2 then
        ShowBg(0, 0, 0, 1)
    elseif bg == 3 then
        local classFile = select(2, UnitClass(unit))
        local c = not (issecretvalue and issecretvalue(classFile)) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if c then ShowBg(c.r * 0.45, c.g * 0.45, c.b * 0.45, 1)
        else      ShowBg(0, 0, 0, 1) end
    elseif bg == 4 then
        ShowBg(db[pre.."BgR"] or 0.1, db[pre.."BgG"] or 0.1,
               db[pre.."BgB"] or 0.1, db[pre.."BgA"] or 1.0)
    end
end

-------------------------------------------------------------------------------
-- Bar border colour  (edge on the sqFrame chrome area)
-------------------------------------------------------------------------------
function ABP:ApplyBarBorderColor(p, unit)
    if not (p.sqFrame and p.sqFrame.SetBackdropBorderColor) then return end
    local db  = self.db
    local pre = UnitPrefix(unit)
    local borderSize = math.max(0, math.min(8, db[pre.."BarBorderSize"] or 1))

    if p.sqFrame.SetBackdrop and p.sqBorderSize ~= borderSize then
        local edgeSize = math.max(1, borderSize)
        p.sqFrame:SetBackdrop({
            bgFile   = WHITE_TEX,
            edgeFile = WHITE_TEX,
            tile     = false,
            edgeSize = edgeSize,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        p.sqFrame:SetBackdropColor(0, 0, 0, 0)
        p.sqBorderSize = borderSize
    end

    if not self.supportsCustomFrameOptions then
        p.sqFrame:SetBackdropBorderColor(0, 0, 0, 0)
        return
    end
    local bc  = db[pre.."BarBC"] or 1
    local r, g, b, a = 0.82, 0.85, 0.90, 0   -- default transparent

    if borderSize == 0 or bc == 1 then      -- Transparent
        a = 0
    elseif bc == 2 then  -- Slate
        r, g, b, a = 0.22, 0.31, 0.40, 1
    elseif bc == 3 then  -- Silver
        r, g, b, a = 0.75, 0.75, 0.75, 1
    else                 -- Custom
        r = db[pre.."BarBR"] or 0.82
        g = db[pre.."BarBG"] or 0.85
        b = db[pre.."BarBB"] or 0.90
        a = 1
    end
    p.sqFrame:SetBackdropBorderColor(r, g, b, a)
end

function ABP:ApplyBarFrameLayout(p, unit)
    if not (p and p.sqFrame and p.clip and unit) then return end

    local db = self.db or DEFAULTS
    local pre = UnitPrefix(unit)
    local lengthOffset = math.max(-80, math.min(120, db[pre.."BarLength"] or 0))
    local heightOffset = math.max(-24, math.min(60, db[pre.."BarHeight"] or 0))
    local baseHeight = math.floor(p.cy * 0.62)
    local height = math.max(10, baseHeight + heightOffset)

    p.sqFrame:ClearAllPoints()
    if p.sqSide == "right" then
        local yOff = -math.floor(p.cy * 0.62) - 2
        p.sqFrame:SetHeight(height + 2)
        p.sqFrame:SetPoint("TOPLEFT",  p.sqGrandpa or p.sqFrame:GetParent(), "TOPLEFT", math.floor(p.cx * 0.38) - lengthOffset, yOff)
        p.sqFrame:SetPoint("TOPRIGHT", p.clip, "TOPLEFT", 1, yOff)
    else
        local yOff = -math.floor(p.cy * 0.32)
        p.sqFrame:SetHeight(height)
        p.sqFrame:SetPoint("TOPLEFT",  p.clip, "TOPRIGHT", 0, yOff)
        p.sqFrame:SetPoint("TOPRIGHT", p.sqRightAnchor or p.sqGrandpa or p.sqFrame:GetParent(), "TOPRIGHT", -4 + lengthOffset, yOff)
    end
end

-------------------------------------------------------------------------------
-- Player class resource row
-------------------------------------------------------------------------------
local function ResolvePowerType(token, fallback)
    if Enum and Enum.PowerType and Enum.PowerType[token] ~= nil then
        return Enum.PowerType[token]
    end
    local legacy = _G["SPELL_POWER_" .. token]
    if legacy ~= nil then
        return legacy
    end
    return fallback
end

local CLASS_RESOURCE_DEFS = {
    DEATHKNIGHT = { kind = "runes", count = 6, iconTexture = "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-SingleRune", color = { 0.09, 0.68, 0.93 } },
    ROGUE       = { kind = "power", powerType = ResolvePowerType("COMBO_POINTS", 4),     iconSpellID = 2098,   color = { 0.95, 0.16, 0.12 } },  -- Eviscerate
    DRUID       = { kind = "power", powerType = ResolvePowerType("COMBO_POINTS", 4),     iconSpellID = 22568,  color = { 1.00, 0.55, 0.15 } },  -- Ferocious Bite
    PALADIN     = { kind = "power", powerType = ResolvePowerType("HOLY_POWER", 9),       iconSpellID = 85256,  color = { 0.96, 0.82, 0.18 } },
    MONK        = { kind = "power", powerType = ResolvePowerType("CHI", 12),             iconSpellID = 100784, color = { 0.19, 0.87, 0.72 } },
    WARLOCK     = { kind = "power", powerType = ResolvePowerType("SOUL_SHARDS", 7),      iconSpellID = 105174, color = { 0.62, 0.32, 0.94 } },
    MAGE        = { kind = "power", powerType = ResolvePowerType("ARCANE_CHARGES", 16),  iconSpellID = 44425,  color = { 0.45, 0.78, 1.00 } },
    EVOKER      = { kind = "power", powerType = ResolvePowerType("ESSENCE", 19),         iconSpellID = 361469, color = { 0.22, 0.82, 0.58 } },
}

local NATIVE_CLASS_POWER_FRAME_NAMES = {
    "RuneFrame",
    "PaladinPowerBarFrame",
    "RogueComboPointBarFrame",
    "MonkHarmonyBarFrame",
    "WarlockPowerFrame",
    "MageArcaneChargesFrame",
    "EssencePlayerFrame",
}

local RUNE_STYLE_TEXTURES = {
    "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-SingleRune",
    "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-SingleRune",
    "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Blood-On",
    "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Frost-On",
    "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Unholy",
    "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Death-On",
}

local COMBO_STYLE_DEFS = {
    { iconSpellID = 2098   },  -- Classic  (Eviscerate)
    { iconSpellID = 1752   },  -- Strike   (Sinister Strike)
    { iconSpellID = 408    },  -- Skull    (Kidney Shot)
    { iconSpellID = 185438 },  -- Shadow   (Shadowstrike)
}

local function GetDeathKnightAutoRuneTexture()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex == 1 then
        return "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Blood-On"
    elseif specIndex == 2 then
        return "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Frost-On"
    elseif specIndex == 3 then
        return "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Unholy"
    end
    return "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-SingleRune"
end

local function ResolveStyleTexture(styleDef)
    if not styleDef then
        return "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    if styleDef.iconTexture then
        return styleDef.iconTexture
    end
    local spellID = styleDef.iconSpellID
    if not spellID then
        return "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellID)
        if tex then return tex end
    end
    if GetSpellTexture then
        local ok, tex = pcall(GetSpellTexture, spellID)
        if ok and tex then return tex end
    end
    if GetSpellInfo then
        local _, _, tex = GetSpellInfo(spellID)
        if tex then return tex end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function GetResourceIconTexture(def)
    local _, classTag = UnitClass("player")
    if def and def.kind == "runes" then
        local idx = (ABP and ABP.db and ABP.db.playerRuneStyle) or 1
        if idx == 1 then
            return GetDeathKnightAutoRuneTexture()
        end
        return RUNE_STYLE_TEXTURES[idx] or RUNE_STYLE_TEXTURES[1]
    end
    if def and def.kind == "power" and (classTag == "ROGUE" or classTag == "DRUID")
        and def.powerType == ResolvePowerType("COMBO_POINTS", 4) then
        local idx = (ABP and ABP.db and ABP.db.playerComboPointStyle) or 1
        return ResolveStyleTexture(COMBO_STYLE_DEFS[idx] or COMBO_STYLE_DEFS[1])
    end
    if def and def.iconTexture then
        return def.iconTexture
    end
    return ResolveStyleTexture(def)
end

local function NormalizeDisplayedPower(powerType, value)
    if issecretvalue and issecretvalue(value) then return nil end
    if not value then return 0 end
    local displayMod = 1
    if powerType and UnitPowerDisplayMod then
        local ok, mod = pcall(UnitPowerDisplayMod, powerType)
        if ok and mod then
            displayMod = mod
        else
            local okLegacy, legacyMod = pcall(UnitPowerDisplayMod, "player", powerType)
            if okLegacy and legacyMod then
                displayMod = legacyMod
            end
        end
    end
    if displayMod and displayMod > 1 then
        return math.floor((value / displayMod) + 0.0001)
    end
    return value
end

local function GetPlayerClassResourceDef()
    local _, classTag = UnitClass("player")
    local def = classTag and CLASS_RESOURCE_DEFS[classTag]
    if not def then return nil end
    if def.kind == "power" then
        local maxPower = def.powerType and UnitPowerMax("player", def.powerType) or 0
        maxPower = NormalizeDisplayedPower(def.powerType, maxPower)
        if not maxPower or maxPower <= 0 then
            return nil
        end
        return def, maxPower
    end
    return def, def.count
end

local function GetClassResourceColor(def)
    if def and def.color then
        return def.color[1], def.color[2], def.color[3]
    end
    local classFile = select(2, UnitClass("player"))
    local c = not (issecretvalue and issecretvalue(classFile)) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then
        return c.r, c.g, c.b
    end
    return 0.82, 0.85, 0.90
end

local function ClearCooldownFrame(frame)
    if not frame then return end
    if frame.Clear then
        frame:Clear()
    elseif CooldownFrame_Clear then
        CooldownFrame_Clear(frame)
    else
        frame:SetCooldown(0, 0)
    end
    frame.abpStart = nil
    frame.abpDuration = nil
    frame:Hide()
end

local function EnsureClassPowerPip(holder, index)
    if holder.pips[index] then
        return holder.pips[index]
    end

    local pip = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    pip:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    pip:SetBackdropColor(MODERN_FIELD[1], MODERN_FIELD[2], MODERN_FIELD[3], 0.90)
    pip:SetBackdropBorderColor(MODERN_BORDER[1], MODERN_BORDER[2], MODERN_BORDER[3], 0.80)

    pip.icon = pip:CreateTexture(nil, "ARTWORK")
    pip.icon:SetPoint("TOPLEFT", 2, -2)
    pip.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    pip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    pip.tint = pip:CreateTexture(nil, "ARTWORK", nil, 1)
    pip.tint:SetAllPoints(pip.icon)

    pip.dim = pip:CreateTexture(nil, "OVERLAY", nil, 2)
    pip.dim:SetAllPoints()

    pip.shine = pip:CreateTexture(nil, "OVERLAY", nil, 3)
    pip.shine:SetColorTexture(1, 1, 1, 0.14)

    pip.circleBorder = pip:CreateTexture(nil, "BACKGROUND", nil, -3)
    pip.circleBorder:SetAllPoints()
    pip.circleFill = pip:CreateTexture(nil, "BACKGROUND", nil, -2)
    pip.circleFill:SetPoint("TOPLEFT", 2, -2)
    pip.circleFill:SetPoint("BOTTOMRIGHT", -2, 2)

    pip.circleBorderMask = pip:CreateMaskTexture()
    pip.circleBorderMask:SetAllPoints(pip.circleBorder)
    pip.circleBorderMask:SetTexture("Interface\\Masks\\CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    pip.circleBorder:AddMaskTexture(pip.circleBorderMask)

    pip.circleFillMask = pip:CreateMaskTexture()
    pip.circleFillMask:SetAllPoints(pip.circleFill)
    pip.circleFillMask:SetTexture("Interface\\Masks\\CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    pip.circleFill:AddMaskTexture(pip.circleFillMask)

    pip.iconMask = pip:CreateMaskTexture()
    pip.iconMask:SetAllPoints(pip.icon)
    pip.iconMask:SetTexture("Interface\\Masks\\CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    pip.tintMask = pip:CreateMaskTexture()
    pip.tintMask:SetAllPoints(pip.tint)
    pip.tintMask:SetTexture("Interface\\Masks\\CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    pip.dimMask = pip:CreateMaskTexture()
    pip.dimMask:SetAllPoints(pip.dim)
    pip.dimMask:SetTexture("Interface\\Masks\\CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    pip.cooldown = CreateFrame("Cooldown", nil, pip, "CooldownFrameTemplate")
    pip.cooldown:SetAllPoints(pip.icon)
    if pip.cooldown.SetDrawEdge then pip.cooldown:SetDrawEdge(false) end
    if pip.cooldown.SetDrawBling then pip.cooldown:SetDrawBling(false) end
    if pip.cooldown.SetHideCountdownNumbers then pip.cooldown:SetHideCountdownNumbers(true) end
    if pip.cooldown.SetReverse then pip.cooldown:SetReverse(true) end
    if pip.cooldown.SetUseCircularEdge then pip.cooldown:SetUseCircularEdge(true) end
    if pip.cooldown.SetSwipeColor then pip.cooldown:SetSwipeColor(0, 0, 0, 0.75) end
    pip.cooldown:Hide()

    pip.timerText = pip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pip.timerText:SetPoint("CENTER", pip, "CENTER", 0, 0)
    pip.timerText:SetJustifyH("CENTER")
    pip.timerText:SetJustifyV("MIDDLE")
    pip.timerText:SetTextColor(1, 0.96, 0.86, 1)
    if pip.timerText.SetShadowOffset then
        pip.timerText:SetShadowOffset(1, -1)
        pip.timerText:SetShadowColor(0, 0, 0, 0.95)
    end
    pip.timerText:Hide()

    holder.pips[index] = pip
    return pip
end

local function SetMaskedTextureState(tex, mask, useMask)
    if not (tex and mask) then return end
    if useMask then
        if not tex.abpMaskApplied and tex.AddMaskTexture then
            tex:AddMaskTexture(mask)
            tex.abpMaskApplied = true
        end
    elseif tex.abpMaskApplied and tex.RemoveMaskTexture then
        tex:RemoveMaskTexture(mask)
        tex.abpMaskApplied = nil
    end
end

local function ApplyClassPowerShape(pip, shape, size, r, g, b, isReady, borderSize)
    local circle = shape == 2
    borderSize = math.max(0, math.min(6, borderSize or 1))
    local inset = math.max(2, borderSize + 1)

    SetMaskedTextureState(pip.icon, pip.iconMask, circle)
    SetMaskedTextureState(pip.tint, pip.tintMask, circle)
    SetMaskedTextureState(pip.dim, pip.dimMask, circle)

    pip.circleBorder:SetShown(circle)
    pip.circleFill:SetShown(circle)
    pip.circleBorder:SetColorTexture(isReady and r or MODERN_BORDER[1], isReady and g or MODERN_BORDER[2], isReady and b or MODERN_BORDER[3], borderSize == 0 and 0 or (isReady and 1 or 0.75))
    pip.circleFill:SetColorTexture(MODERN_FIELD[1], MODERN_FIELD[2], MODERN_FIELD[3], isReady and 0.92 or 0.82)

    if circle then
        pip:SetBackdropColor(0, 0, 0, 0)
        pip:SetBackdropBorderColor(0, 0, 0, 0)
        pip.circleFill:ClearAllPoints()
        pip.circleFill:SetPoint("TOPLEFT", inset, -inset)
        pip.circleFill:SetPoint("BOTTOMRIGHT", -inset, inset)
        pip.icon:ClearAllPoints()
        pip.icon:SetPoint("TOPLEFT", inset, -inset)
        pip.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        pip.tint:ClearAllPoints()
        pip.tint:SetAllPoints(pip.icon)
        pip.dim:ClearAllPoints()
        pip.dim:SetAllPoints(pip.icon)
        pip.cooldown:ClearAllPoints()
        pip.cooldown:SetPoint("TOPLEFT", pip.icon, "TOPLEFT", 0, 0)
        pip.cooldown:SetPoint("BOTTOMRIGHT", pip.icon, "BOTTOMRIGHT", 0, 0)
    else
        pip.icon:ClearAllPoints()
        pip.icon:SetPoint("TOPLEFT", inset, -inset)
        pip.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        pip.tint:ClearAllPoints()
        pip.tint:SetAllPoints(pip.icon)
        pip.dim:ClearAllPoints()
        pip.dim:SetAllPoints()
        pip.cooldown:ClearAllPoints()
        pip.cooldown:SetAllPoints(pip.icon)
    end
end

local function ApplyClassPowerPipState(pip, shape, isReady, r, g, b, iconTexture, size, dimAlpha, borderSize)
    borderSize = math.max(0, math.min(6, borderSize or 1))
    if pip.abpBorderSize ~= borderSize then
        local edgeSize = math.max(1, borderSize)
        pip:SetBackdrop({
            bgFile = WHITE_TEX,
            edgeFile = WHITE_TEX,
            tile = false,
            edgeSize = edgeSize,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        pip.abpBorderSize = borderSize
    end

    pip.icon:SetTexture(iconTexture)
    pip.icon:SetDesaturated(not isReady)
    pip.icon:SetVertexColor(isReady and 1 or 0.50, isReady and 1 or 0.50, isReady and 1 or 0.50, isReady and 1 or 0.60)
    pip.tint:SetColorTexture(r, g, b, isReady and 0.18 or 0.05)
    pip.dim:SetColorTexture(0, 0, 0, isReady and 0.10 or (dimAlpha or 0.45))
    pip.shine:ClearAllPoints()
    pip.shine:SetPoint("TOPLEFT", 1, -1)
    pip.shine:SetPoint("TOPRIGHT", -1, -1)
    pip.shine:SetHeight(math.max(2, math.floor(size * 0.22)))
    pip.shine:SetShown(isReady)
    pip:SetBackdropBorderColor(isReady and r or MODERN_BORDER[1], isReady and g or MODERN_BORDER[2], isReady and b or MODERN_BORDER[3], borderSize == 0 and 0 or (isReady and 1 or 0.70))
    pip:SetBackdropColor(MODERN_FIELD[1], MODERN_FIELD[2], MODERN_FIELD[3], isReady and 0.95 or 0.82)
    ApplyClassPowerShape(pip, shape, size, r, g, b, isReady, borderSize)
    if pip.timerText then
        pip.timerText:SetFont(ABP_UI_FONT, math.max(8, math.floor(size * 0.50)), "OUTLINE")
        if isReady then
            pip.timerText:Hide()
            pip.timerText:SetText("")
        end
    end
end

local function FormatRuneTimerText(remaining)
    if remaining >= 10 then
        return tostring(math.ceil(remaining))
    elseif remaining >= 1 then
        return string.format("%.1f", remaining)
    elseif remaining > 0 then
        return string.format("%.1f", remaining)
    end
    return ""
end

function ABP:GetPlayerPortraitState()
    -- Only a portrait inside the real Blizzard PlayerFrame may own class
    -- resources. Retail does not always use the legacy PlayerPortrait global,
    -- while many unrelated windows also request a portrait for unit "player".
    local function BelongsToPlayerFrame(texture)
        local region = texture
        for _ = 1, 20 do
            if not region then return false end
            if region == PlayerFrame then return true end
            region = region.GetParent and region:GetParent() or nil
        end
        return false
    end

    if PlayerPortrait then
        local state = self.portraits[PlayerPortrait]
        if state and state.unit == "player" and BelongsToPlayerFrame(PlayerPortrait) then
            return state
        end
    end
    for texture, state in pairs(self.portraits) do
        if state.unit == "player" and BelongsToPlayerFrame(texture) then
            return state
        end
    end
end

function ABP:HidePlayerClassPower(p)
    local state = p or self:GetPlayerPortraitState()
    if state and state.classPowerFrame then
        for _, pip in ipairs(state.classPowerFrame.pips or {}) do
            if pip and pip.timerText then
                pip.timerText:Hide()
                pip.timerText:SetText("")
            end
        end
        state.classPowerFrame:Hide()
    end
end

function ABP:UpdatePlayerClassPowerTimerText()
    local state = self:GetPlayerPortraitState()
    local holder = state and state.classPowerFrame
    if not (holder and holder:IsShown()) then return end

    local showTimers = self.db and self.db.playerRuneTimerText
    for _, pip in ipairs(holder.pips or {}) do
        if pip and pip.timerText then
            if showTimers and pip.cooldown and pip.cooldown.abpStart and pip.cooldown.abpDuration and pip.cooldown.abpDuration > 0 then
                local remaining = (pip.cooldown.abpStart + pip.cooldown.abpDuration) - GetTime()
                if remaining > 0.05 then
                    pip.timerText:SetText(FormatRuneTimerText(remaining))
                    pip.timerText:Show()
                else
                    pip.timerText:Hide()
                    pip.timerText:SetText("")
                end
            else
                pip.timerText:Hide()
                pip.timerText:SetText("")
            end
        end
    end
end

local function IsUsingCustomRunes()
    local _, classTag = UnitClass("player")
    if classTag ~= "DEATHKNIGHT" then
        return true
    end
    return not (ABP and ABP.db and ABP.db.playerUseCustomRunes == false)
end

function ABP:UpdateBlizzardClassPowerVisibility()
    if self.isClassicClient or not self.db then return end
    local state = self:GetPlayerPortraitState()
    local holder = state and state.classPowerFrame
    local shouldHide = self.db.playerClassPowerEnabled
        and self.db.playerClassPowerHideBlizzard
        and IsUsingCustomRunes()
        and holder and holder:IsShown()
    for _, frameName in ipairs(NATIVE_CLASS_POWER_FRAME_NAMES) do
        local frame = _G[frameName]
        if frame then
            SetNativeTextureHidden(frame, shouldHide)
        end
    end
end

function ABP:RefreshPlayerClassPower(p)
    if self.isClassicClient or not self.db then return end

    local canonicalState = self:GetPlayerPortraitState()
    if p and p ~= canonicalState then
        -- Clean up a row created by an older build or a non-unit portrait that
        -- happened to be populated with the player unit token.
        self:HidePlayerClassPower(p)
        return
    end
    local state = canonicalState
    if not self.db.playerClassPowerEnabled then
        self:HidePlayerClassPower(state)
        self:UpdateBlizzardClassPowerVisibility()
        return
    end

    if not (state and state.clip and state.clip:IsShown() and state.sqFrame) then
        self:HidePlayerClassPower(state)
        self:UpdateBlizzardClassPowerVisibility()
        return
    end

    local def, count = GetPlayerClassResourceDef()
    if not def or not count or count < 1 then
        self:HidePlayerClassPower(state)
        self:UpdateBlizzardClassPowerVisibility()
        return
    end
    if def.kind == "runes" and not IsUsingCustomRunes() then
        self:HidePlayerClassPower(state)
        self:UpdateBlizzardClassPowerVisibility()
        return
    end

    local holder = state.classPowerFrame
    if not holder then
        holder = CreateFrame("Frame", nil, state.sqFrame:GetParent())
        holder:SetFrameStrata(state.sqFrame:GetFrameStrata())
        holder.pips = {}
        state.classPowerFrame = holder
    end

    local size = math.max(12, math.floor(self.db.playerClassPowerSize or 18))
    local spacing = math.max(0, math.floor(self.db.playerClassPowerSpacing or 4))
    local pipBorderSize = math.max(0, math.min(6, math.floor(self.db.playerClassPowerBorderSize or 1)))
    local shape = self.db.playerClassPowerShape or 1
    local xOffset = math.floor(self.db.playerClassPowerXOffset or 0)
    local yOffset = math.floor(self.db.playerClassPowerYOffset or -6)
    local totalWidth = (count * size) + (math.max(0, count - 1) * spacing)
    local iconTexture = GetResourceIconTexture(def)
    local r, g, b = GetClassResourceColor(def)
    local currentPower = 0
    if def.powerType then
        currentPower = NormalizeDisplayedPower(def.powerType, UnitPower("player", def.powerType))
        if currentPower == nil then
            -- Restricted power cannot be counted into addon-owned pips. Keep
            -- Blizzard's native display available rather than guessing a count.
            self:HidePlayerClassPower(state)
            self:UpdateBlizzardClassPowerVisibility()
            return
        end
    end
    local runeShade = math.max(0.12, math.min(0.85, (self.db.playerRuneCooldownShade or 38) / 100))
    local showRuneTimers = self.db.playerRuneTimerText and def.kind == "runes"

    holder:ClearAllPoints()
    holder:SetPoint("TOP", state.sqFrame, "BOTTOM", xOffset, yOffset)
    holder:SetSize(totalWidth, size)
    holder:SetFrameLevel((state.sqFrame:GetFrameLevel() or state.clip:GetFrameLevel()) + 8)

    for i = 1, count do
        local pip = EnsureClassPowerPip(holder, i)
        pip:ClearAllPoints()
        pip:SetPoint("LEFT", holder, "LEFT", (i - 1) * (size + spacing), 0)
        pip:SetSize(size, size)

        local isReady = false
        if def.kind == "runes" then
            local start, duration, runeReady = GetRuneCooldown(i)
            if issecretvalue and (issecretvalue(start) or issecretvalue(duration) or issecretvalue(runeReady)) then
                self:HidePlayerClassPower(state)
                self:UpdateBlizzardClassPowerVisibility()
                return
            end
            isReady = runeReady or not duration or duration <= 0 or start == 0
            if isReady then
                ClearCooldownFrame(pip.cooldown)
            else
                pip.cooldown.abpStart = start
                pip.cooldown.abpDuration = duration
                pip.cooldown:Show()
                pip.cooldown:SetCooldown(start, duration)
                if pip.cooldown.SetSwipeColor then pip.cooldown:SetSwipeColor(0, 0, 0, runeShade) end
            end
        else
            isReady = i <= currentPower
            ClearCooldownFrame(pip.cooldown)
        end

        local pipDimAlpha = (def.kind == "runes" and not isReady) and runeShade or nil
        ApplyClassPowerPipState(pip, shape, isReady, r, g, b, iconTexture, size, pipDimAlpha, pipBorderSize)
        if not showRuneTimers and pip.timerText then
            pip.timerText:Hide()
            pip.timerText:SetText("")
        end
        pip:Show()
    end

    for i = count + 1, #(holder.pips or {}) do
        local pip = holder.pips[i]
        if pip then
            ClearCooldownFrame(pip.cooldown)
            pip:Hide()
        end
    end

    holder:Show()
    self:UpdatePlayerClassPowerTimerText()
    self:UpdateBlizzardClassPowerVisibility()
end

-------------------------------------------------------------------------------
-- Health / resource bar colours
-------------------------------------------------------------------------------
local function ApplyGradient(tex, s, e)
    if not (tex and s and e) then return false end
    if CreateColor then
        return pcall(function()
            tex:SetGradient("HORIZONTAL",
                CreateColor(s[1], s[2], s[3], 1),
                CreateColor(e[1], e[2], e[3], 1))
        end)
    end
    return pcall(tex.SetGradientAlpha, tex, "HORIZONTAL",
        s[1], s[2], s[3], 1, e[1], e[2], e[3], 1)
end

local function ResolvePath(root, ...)
    local node = root
    for i = 1, select("#", ...) do
        node = node and node[select(i, ...)]
    end
    return node
end

local function FirstStatusBar(...)
    for i = 1, select("#", ...) do
        local bar = select(i, ...)
        if type(bar) == "function" then bar = bar() end
        if bar and bar.GetStatusBarTexture and bar.SetStatusBarColor then
            return bar
        end
    end
end

local function PartyIndexFromUnit(unit)
    if not unit then return nil end
    local idx = tonumber(unit:match("^party(%d+)$"))
    if idx and idx >= 1 and idx <= 4 then return idx end
end

local function FindStatusBarRecursive(root, wantHealth, depth, seen)
    if not (root and root.GetChildren) then return nil end
    if root.IsForbidden and root:IsForbidden() then return nil end
    if depth and depth < 0 then return nil end
    seen = seen or {}
    if seen[root] then return nil end
    seen[root] = true

    local ok, children = pcall(function() return { root:GetChildren() } end)
    if not ok then return nil end
    for _, child in ipairs(children) do
        if child and not seen[child] and not (child.IsForbidden and child:IsForbidden()) then
            local name = ReadableTextureText(SafeRegionValue(child, child.GetName))
            local isStatusBar = child.GetStatusBarTexture and child.SetStatusBarColor
            if isStatusBar and name ~= "" then
                local low = name
                if wantHealth then
                    if low:find("healthbar", 1, true) then
                        return child
                    end
                else
                    if low:find("manabar", 1, true)
                        or low:find("powerbar", 1, true)
                        or low:find("resourcebar", 1, true) then
                        return child
                    end
                end
            end
            local found = FindStatusBarRecursive(child, wantHealth, (depth or 4) - 1, seen)
            if found then return found end
        end
    end
    return nil
end

local function GetPartyRootFrame(index)
    return _G["PartyMemberFrame"..index]
        or _G["PartyFrameMemberFrame"..index]
        or _G["CompactPartyFrameMember"..index]
        or _G["CompactPartyFrameMemberFrame"..index]
end

-- TWW-confirmed frame paths sourced from HealthBarColor addon (Slothpala, 3.7.0).
-- Each unit lists the TWW-correct path first, then legacy fallbacks so the
-- same code works if Blizzard restructures the frames again in a future patch.
local function GetUnitBarFrames(unit)
    if unit == "player" then
        local main = ResolvePath(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain")
        return
            FirstStatusBar(
                -- TWW (HealthBarsContainer introduced in Dragonflight/TWW)
                ResolvePath(main, "HealthBarsContainer", "HealthBar"),
                -- pre-TWW fallbacks
                ResolvePath(main, "HealthBarArea", "HealthBar"),
                ResolvePath(main, "HealthBar"),
                _G.PlayerFrameHealthBar,
                PlayerFrame and PlayerFrame.HealthBar,
                PlayerFrame and PlayerFrame.healthbar,
                function() return FindStatusBarRecursive(main, true) end,
                function() return FindStatusBarRecursive(PlayerFrame, true) end),
            FirstStatusBar(
                -- TWW
                ResolvePath(main, "ManaBarArea", "ManaBar"),
                -- pre-TWW fallbacks
                ResolvePath(main, "PowerBarArea", "PowerBar"),
                ResolvePath(main, "ManaBar"),
                ResolvePath(main, "PowerBar"),
                _G.PlayerFrameManaBar,
                _G.PlayerFramePowerBar,
                PlayerFrame and PlayerFrame.ManaBar,
                PlayerFrame and PlayerFrame.PowerBar,
                PlayerFrame and PlayerFrame.manabar,
                PlayerFrame and PlayerFrame.powerBar,
                function() return FindStatusBarRecursive(main, false) end,
                function() return FindStatusBarRecursive(PlayerFrame, false) end)

    elseif unit == "pet" then
        local main = PetFrame and (
            PetFrame.PetFrameContentMain
            or ResolvePath(PetFrame, "PetFrameContent", "PetFrameContentMain")
            or ResolvePath(PetFrame, "PetFrameContentMain"))
        return
            FirstStatusBar(
                ResolvePath(main, "HealthBarsContainer", "HealthBar"),
                ResolvePath(main, "HealthBarArea", "HealthBar"),
                ResolvePath(main, "HealthBar"),
                _G.PetFrameHealthBar,
                PetFrame and PetFrame.HealthBar,
                function() return FindStatusBarRecursive(main, true) end,
                function() return FindStatusBarRecursive(PetFrame, true) end),
            FirstStatusBar(
                ResolvePath(main, "ManaBar"),
                ResolvePath(main, "ManaBarArea", "ManaBar"),
                ResolvePath(main, "PowerBarArea", "PowerBar"),
                ResolvePath(main, "PowerBar"),
                _G.PetFrameManaBar,
                _G.PetFramePowerBar,
                PetFrame and PetFrame.ManaBar,
                PetFrame and PetFrame.PowerBar,
                function() return FindStatusBarRecursive(main, false) end,
                function() return FindStatusBarRecursive(PetFrame, false) end)

    elseif unit == "target" then
        local main = ResolvePath(TargetFrame, "TargetFrameContent", "TargetFrameContentMain")
        return
            FirstStatusBar(
                ResolvePath(main, "HealthBarsContainer", "HealthBar"),
                ResolvePath(main, "HealthBarArea", "HealthBar"),
                ResolvePath(main, "HealthBar"),
                _G.TargetFrameHealthBar,
                function() return FindStatusBarRecursive(main, true) end,
                function() return FindStatusBarRecursive(TargetFrame, true) end),
            FirstStatusBar(
                -- TWW: target/focus mana bar lives directly under main (no ManaBarArea wrapper)
                ResolvePath(main, "ManaBar"),
                ResolvePath(main, "ManaBarArea", "ManaBar"),
                ResolvePath(main, "PowerBarArea", "PowerBar"),
                ResolvePath(main, "PowerBar"),
                _G.TargetFrameManaBar,
                _G.TargetFramePowerBar,
                function() return FindStatusBarRecursive(main, false) end,
                function() return FindStatusBarRecursive(TargetFrame, false) end)

    elseif unit == "focus" then
        local main = ResolvePath(FocusFrame, "TargetFrameContent", "TargetFrameContentMain")
        return
            FirstStatusBar(
                ResolvePath(main, "HealthBarsContainer", "HealthBar"),
                ResolvePath(main, "HealthBarArea", "HealthBar"),
                ResolvePath(main, "HealthBar"),
                _G.FocusFrameHealthBar,
                function() return FindStatusBarRecursive(main, true) end,
                function() return FindStatusBarRecursive(FocusFrame, true) end),
            FirstStatusBar(
                ResolvePath(main, "ManaBar"),
                ResolvePath(main, "ManaBarArea", "ManaBar"),
                ResolvePath(main, "PowerBarArea", "PowerBar"),
                ResolvePath(main, "PowerBar"),
                _G.FocusFrameManaBar,
                _G.FocusFramePowerBar,
                function() return FindStatusBarRecursive(main, false) end,
                function() return FindStatusBarRecursive(FocusFrame, false) end)
    end

    local partyIndex = PartyIndexFromUnit(unit)
    if partyIndex then
        -- TWW party frames live under the global PartyFrame as MemberFrame1..4
        local twwMember = ResolvePath(_G.PartyFrame, "MemberFrame"..partyIndex)
        -- Pre-TWW party frames used individual globals like PartyMemberFrame1
        local oldFrame  = GetPartyRootFrame(partyIndex)
        local oldMain   = oldFrame and (
            oldFrame.PartyMemberFrameContentMain
            or ResolvePath(oldFrame, "PartyMemberFrameContent", "PartyMemberFrameContentMain")
            or ResolvePath(oldFrame, "PartyFrameContent",       "PartyFrameContentMain"))
        return
            FirstStatusBar(
                -- TWW: HealthBarContainer (singular Bar) under MemberFrameN
                ResolvePath(twwMember, "HealthBarContainer", "HealthBar"),
                -- pre-TWW fallbacks
                ResolvePath(oldMain, "HealthBarArea", "HealthBar"),
                ResolvePath(oldMain, "HealthBar"),
                oldFrame and oldFrame.HealthBar,
                _G["PartyMemberFrame"..partyIndex.."HealthBar"],
                function() return FindStatusBarRecursive(oldMain,   true) end,
                function() return FindStatusBarRecursive(oldFrame,  true) end,
                function() return FindStatusBarRecursive(twwMember, true) end),
            FirstStatusBar(
                -- TWW
                ResolvePath(twwMember, "ManaBar"),
                -- pre-TWW fallbacks
                ResolvePath(oldMain, "ManaBarArea",  "ManaBar"),
                ResolvePath(oldMain, "PowerBarArea", "PowerBar"),
                ResolvePath(oldMain, "ManaBar"),
                ResolvePath(oldMain, "PowerBar"),
                oldFrame and oldFrame.ManaBar,
                oldFrame and oldFrame.PowerBar,
                _G["PartyMemberFrame"..partyIndex.."ManaBar"],
                _G["PartyMemberFrame"..partyIndex.."PowerBar"],
                function() return FindStatusBarRecursive(oldMain,   false) end,
                function() return FindStatusBarRecursive(oldFrame,  false) end,
                function() return FindStatusBarRecursive(twwMember, false) end)
    end
end

local function GetDefaultHealthColor(unit)
    if not unit or not UnitExists(unit) then
        return 0.0, 0.85, 0.15
    end
    if UnitIsPlayer(unit) and UnitIsConnected and not UnitIsConnected(unit) then
        return 0.55, 0.55, 0.55
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
        return 0.55, 0.55, 0.55
    end
    if UnitIsTapDenied and UnitIsTapDenied(unit) then
        return 0.55, 0.55, 0.55
    end
    if unit == "player" then
        return 0.0, 0.85, 0.15
    end
    if UnitIsPlayer(unit) then
        local classFile = select(2, UnitClass(unit))
        local c = not (issecretvalue and issecretvalue(classFile)) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if c then return c.r, c.g, c.b end
    end
    if UnitSelectionColor then
        local r, g, b = UnitSelectionColor(unit)
        if r and not (r > 0.95 and g > 0.95 and b > 0.95) then
            return r, g, b
        end
    end
    if UnitReaction and FACTION_BAR_COLORS then
        local reaction = UnitReaction(unit, "player")
        local c = reaction and FACTION_BAR_COLORS[reaction]
        if c then return c.r, c.g, c.b end
    end
    if UnitCanAttack and UnitCanAttack("player", unit) then
        if UnitCanAttack(unit, "player") then
            return 0.9, 0.05, 0.05
        end
        return 1.0, 0.82, 0.0
    end
    if UnitIsFriend and UnitIsFriend("player", unit) then
        return 0.0, 0.85, 0.15
    end
    return 0.0, 0.85, 0.15
end

local function GetClassColor(unit)
    if not unit or not UnitExists(unit) then return nil end
    local classFile = select(2, UnitClass(unit))
    local c = not (issecretvalue and issecretvalue(classFile)) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return nil
end

local function GetDefaultResourceColor(unit)
    if not unit or not UnitExists(unit) then
        return 0.0, 0.55, 1.0
    end
    local _, token = UnitPowerType(unit)
    local info = PowerBarColor and (PowerBarColor[token] or PowerBarColor[UnitPowerType(unit)])
    if info then
        return info.r or info[1] or 0.0,
               info.g or info[2] or 0.55,
               info.b or info[3] or 1.0
    end
    return 0.0, 0.55, 1.0
end

local function DarkenColor(r, g, b, factor)
    factor = factor or 0.55
    return r * factor, g * factor, b * factor
end

local barCustomMode  = {}   -- true while we have custom styling applied to a bar
local barOrigTexture = {}   -- original texture state saved before first replacement
local barVisualState = {}   -- last custom style we applied to a bar
local barStyleOverlay = {}  -- desaturated copy of Blizzard's original fill for "pop"
local barShineOverlay = {}  -- top highlight strip
local barShadowOverlay = {} -- bottom shading strip
local barGlowOverlay = {}   -- soft color bloom
local barFillOverlay = {}   -- Classic/TBC cover fill to hide Blizzard's repaint flicker
local squareBarFillOverlay = {} -- Retail target/focus fill with a straight portrait-side edge
local squareBarFillState = {}
local squareBarFillAnchoredTex = {}
local barNativeFillHooked = {}
local barNativeFillGuard = {}
local barTextureReplaced = {} -- true only when we swapped the fill to ABP_BAR_TEX (Gradient mode)
local barRealtimeColorHooked = {}
local barRealtimeColorUnit = {}
local barColorReapplyGuard = {} -- reentrancy guard for the retail resource-bar recolor hook
local barFillColorHooked = {}   -- keyed by fill texture: SetVertexColor/SetGradient hooked
local barStyledResource = {}    -- unit -> resource bar we last styled (cheap burst reclamp)

local function ColorsApproximatelyEqual(a, b)
    if a == b then return true end
    if a == nil or b == nil then return false end
    return math.abs(a - b) < 0.002
end

local function ColorTripletsEqual(a, b)
    return a and b
        and ColorsApproximatelyEqual(a[1], b[1])
        and ColorsApproximatelyEqual(a[2], b[2])
        and ColorsApproximatelyEqual(a[3], b[3])
end

local function BarVisualStateMatches(state, mode, startColor, endColor, useGloss, useShine, useShadow, useGlow, texturePath)
    return state
        and state.mode == mode
        and state.texturePath == texturePath
        and state.useGloss == (useGloss and true or false)
        and state.useShine == (useShine and true or false)
        and state.useShadow == (useShadow and true or false)
        and state.useGlow == (useGlow and true or false)
        and ColorTripletsEqual(state.startColor, startColor)
        and ColorTripletsEqual(state.endColor, endColor)
end

local function SaveBarVisualState(bar, mode, startColor, endColor, useGloss, useShine, useShadow, useGlow, texturePath)
    barVisualState[bar] = {
        mode = mode,
        texturePath = texturePath,
        startColor = { startColor[1], startColor[2], startColor[3] },
        endColor = { endColor[1], endColor[2], endColor[3] },
        useGloss = useGloss and true or false,
        useShine = useShine and true or false,
        useShadow = useShadow and true or false,
        useGlow = useGlow and true or false,
    }
end

-- We deliberately do NOT use HookScript("OnValueChanged") on any bar.
-- Hooking a secure Blizzard UnitFrame's script taints the entire
-- SetValue → OnValueChanged execution chain, causing TextStatusBar.lua to
-- crash with "attempt to compare a secret number value".
-- Our UNIT_HEALTH / UNIT_POWER_UPDATE event handlers + the 0.25 s OnUpdate
-- timer are sufficient to keep custom colours current without any hooks.
--
-- We also never write bar.lockColor: it is read by Blizzard's secure
-- HealthBar_OnValueChanged inside the SetValue chain.  Any addon-written field
-- read in that context taints the execution and poisons the secret health value,
-- causing a "attempt to compare a secret number value" crash.

local ABP_BAR_TEX = ABP_MEDIA.textures.smooth or WHITE_TEX

local function GetBarTexturePath(index)
    index = tonumber(index) or 1
    return BAR_TEXTURE_PATHS[index] or BAR_TEXTURE_PATHS[1] or ABP_BAR_TEX
end

local function SaveTexCoords(tex)
    if not (tex and tex.GetTexCoord) then return nil end
    local coords = { tex:GetTexCoord() }
    return (#coords > 0) and coords or nil
end

local function SaveBarOrigTexture(bar)
    if barOrigTexture[bar] ~= nil then return end   -- already saved once
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not tex then
        barOrigTexture[bar] = false
        return
    end

    local path = SafeRegionValue(tex, tex.GetTexture)
    local atlas = SafeRegionValue(tex, tex.GetAtlas)
    local coords = SaveTexCoords(tex)

    -- TWW unit bars can use atlas-backed fills. Restoring only the underlying
    -- texture sheet recreates the "thin broken line" until /reload, so we
    -- preserve atlas + texcoord state as well as the raw texture.
    if atlas or coords or (path ~= nil and path ~= 0) then
        barOrigTexture[bar] = {
            texture = (path ~= nil and path ~= 0) and path or false,
            atlas   = atlas,
            coords  = coords,
        }
    else
        barOrigTexture[bar] = false
    end
end

local function ClearTextureGradient(tex)
    if not tex then return end
    ApplyGradient(tex, { 1, 1, 1 }, { 1, 1, 1 })
end

local function ApplyGradientAlphaCompat(tex, orientation, sr, sg, sb, sa, er, eg, eb, ea)
    if not (tex and tex.SetGradientAlpha) then return false end
    return pcall(tex.SetGradientAlpha, tex, orientation, sr, sg, sb, sa, er, eg, eb, ea)
end

local function RestoreBarOrigTexture(bar)
    local orig = barOrigTexture[bar]
    if not orig then return false end

    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not tex then return false end

    ClearTextureGradient(tex)

    if orig.atlas and tex.SetAtlas then
        tex:SetAtlas(orig.atlas)
    elseif orig.texture and tex.SetTexture then
        tex:SetTexture(orig.texture)
    end

    if tex.SetTexCoord then
        if orig.coords then
            tex:SetTexCoord(unpack(orig.coords))
        else
            tex:SetTexCoord(0, 1, 0, 1)
        end
    end

    return true
end

local function EnsureBarStyleOverlay(bar)
    local overlay = barStyleOverlay[bar]
    if overlay then return overlay end

    overlay = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    overlay:Hide()
    if overlay.SetBlendMode then overlay:SetBlendMode("ADD") end
    if overlay.SetAlpha then overlay:SetAlpha(0.35) end
    barStyleOverlay[bar] = overlay
    return overlay
end

local function EnsureBarEffectTexture(store, bar, layer, subLevel, blendMode)
    local tex = store[bar]
    if tex then return tex end

    tex = bar:CreateTexture(nil, layer or "OVERLAY", nil, subLevel or 0)
    tex:Hide()
    if tex.SetBlendMode and blendMode then tex:SetBlendMode(blendMode) end
    store[bar] = tex
    return tex
end

local function HideBarStyleOverlay(bar)
    local overlay = barStyleOverlay[bar]
    if overlay then overlay:Hide() end
end

local function HideBarShineOverlay(bar)
    local overlay = barShineOverlay[bar]
    if overlay then overlay:Hide() end
end

local function HideBarShadowOverlay(bar)
    local overlay = barShadowOverlay[bar]
    if overlay then overlay:Hide() end
end

local function HideBarGlowOverlay(bar)
    local overlay = barGlowOverlay[bar]
    if overlay then overlay:Hide() end
end

local function HideClassicBarFillOverlay(bar)
    local overlay = barFillOverlay[bar]
    if overlay then overlay:Hide() end
end

local function HideSquareBarFillOverlay(bar)
    local overlay = squareBarFillOverlay[bar]
    if overlay then overlay:Hide() end
    squareBarFillState[bar] = nil
end

local function SuppressClassicNativeBarFill(bar)
    if not ABP.isClassicClient then return nil end
    if not (bar and bar.GetStatusBarTexture) then return nil end

    local tex = bar:GetStatusBarTexture()
    if not tex then return nil end

    -- Force the native fill to alpha 0.  We deliberately do NOT Hide() it:
    -- Blizzard's StatusBar C++ resizes this texture in response to SetValue,
    -- and a Hidden texture can be skipped by some Blizzard update paths.
    -- Alpha 0 keeps it invisible while still receiving layout updates.
    if tex.SetAlpha then tex:SetAlpha(0) end
    if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 0) end

    if barNativeFillHooked[tex] or not hooksecurefunc then return tex end
    barNativeFillHooked[tex] = true

    if tex.SetAlpha then
        pcall(hooksecurefunc, tex, "SetAlpha", function(t, alpha)
            local target = (t and t.SetAlpha) and t or tex
            local nextAlpha = (target == t) and alpha or t
            if barNativeFillGuard[target] or nextAlpha == 0 then return end
            barNativeFillGuard[target] = true
            target:SetAlpha(0)
            barNativeFillGuard[target] = nil
        end)
    end
    if tex.SetVertexColor then
        pcall(hooksecurefunc, tex, "SetVertexColor", function(t, r, g, b, a)
            local target = (t and t.SetVertexColor) and t or tex
            local nextAlpha = (target == t) and a or b
            if barNativeFillGuard[target] or nextAlpha == 0 then return end
            barNativeFillGuard[target] = true
            target:SetVertexColor(1, 1, 1, 0)
            barNativeFillGuard[target] = nil
        end)
    end
    -- Some Blizzard update paths Hide()/Show() the fill texture instead of
    -- (or in addition to) changing its alpha.  On a Show() the texture would
    -- briefly render with whatever alpha/colour the C++ side left on it before
    -- our next event-driven Apply re-zeros it -- visible as the regen-tick
    -- flicker on the mana / focus bars.  Re-zero alpha+colour on every Show.
    if tex.HookScript then
        pcall(tex.HookScript, tex, "OnShow", function(t)
            if barNativeFillGuard[t] then return end
            barNativeFillGuard[t] = true
            if t.SetAlpha then t:SetAlpha(0) end
            if t.SetVertexColor then t:SetVertexColor(1, 1, 1, 0) end
            barNativeFillGuard[t] = nil
        end)
    end

    return tex
end

local function HideAllBarEffects(bar)
    HideBarStyleOverlay(bar)
    HideBarShineOverlay(bar)
    HideBarShadowOverlay(bar)
    HideBarGlowOverlay(bar)
end

local function ApplyBarStyleOverlay(bar)
    local orig = barOrigTexture[bar]
    if not orig then
        HideBarStyleOverlay(bar)
        return
    end

    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not tex then
        HideBarStyleOverlay(bar)
        return
    end

    local overlay = EnsureBarStyleOverlay(bar)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", tex, "TOPLEFT")
    overlay:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT")
    if overlay.SetAlpha then overlay:SetAlpha(0.35) end

    if orig.atlas and overlay.SetAtlas then
        overlay:SetAtlas(orig.atlas)
    elseif orig.texture and overlay.SetTexture then
        overlay:SetTexture(orig.texture)
    else
        overlay:Hide()
        return
    end

    if overlay.SetTexCoord then
        if orig.coords then
            overlay:SetTexCoord(unpack(orig.coords))
        else
            overlay:SetTexCoord(0, 1, 0, 1)
        end
    end

    if overlay.SetDesaturated then
        overlay:SetDesaturated(true)
    end
    if overlay.SetVertexColor then
        overlay:SetVertexColor(1, 1, 1, 1)
    end
    overlay:Show()
end

local function ApplyBarShineOverlay(bar)
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not tex then
        HideBarShineOverlay(bar)
        return
    end

    local overlay = EnsureBarEffectTexture(barShineOverlay, bar, "OVERLAY", 2, "ADD")
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", tex, "TOPLEFT")
    overlay:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT")
    overlay:SetTexture(WHITE_TEX)
    if overlay.SetVertexColor then overlay:SetVertexColor(1, 1, 1, 1) end
    if not ApplyGradientAlphaCompat(overlay, "VERTICAL", 1, 1, 1, 0.22, 1, 1, 1, 0.00) then
        if overlay.SetAlpha then overlay:SetAlpha(0.12) end
    end
    overlay:Show()
end

local function ApplyBarShadowOverlay(bar)
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not tex then
        HideBarShadowOverlay(bar)
        return
    end

    local overlay = EnsureBarEffectTexture(barShadowOverlay, bar, "OVERLAY", 3, "BLEND")
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", tex, "TOPLEFT")
    overlay:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT")
    overlay:SetTexture(WHITE_TEX)
    if overlay.SetVertexColor then overlay:SetVertexColor(0, 0, 0, 1) end
    if not ApplyGradientAlphaCompat(overlay, "VERTICAL", 0, 0, 0, 0.00, 0, 0, 0, 0.20) then
        if overlay.SetAlpha then overlay:SetAlpha(0.10) end
    end
    overlay:Show()
end

local function ApplyBarGlowOverlay(bar, color)
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not tex then
        HideBarGlowOverlay(bar)
        return
    end

    local r, g, b = color[1] or 1, color[2] or 1, color[3] or 1
    local overlay = EnsureBarEffectTexture(barGlowOverlay, bar, "OVERLAY", 0, "ADD")
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", tex, "TOPLEFT")
    overlay:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT")
    overlay:SetTexture(WHITE_TEX)
    if overlay.SetVertexColor then overlay:SetVertexColor(r, g, b, 1) end
    if not ApplyGradientAlphaCompat(overlay, "VERTICAL", r, g, b, 0.12, r, g, b, 0.04) then
        if overlay.SetAlpha then overlay:SetAlpha(0.08) end
    end
    overlay:Show()
end

local barFillOverlayState = {}
local barFillOverlayAnchoredTex = {}

local function ClassicBarFillStateMatches(state, mode, startColor, endColor, texturePath)
    return state
        and state.mode == mode
        and state.texturePath == texturePath
        and ColorTripletsEqual(state.startColor, startColor)
        and ColorTripletsEqual(state.endColor, endColor or startColor)
end

local function ApplyClassicBarFillOverlay(bar, mode, startColor, endColor, texturePath)
    if not ABP.isClassicClient then return end
    if not (bar and bar.GetStatusBarTexture) then return end

    local tex = SuppressClassicNativeBarFill(bar)
    if not tex then
        HideClassicBarFillOverlay(bar)
        barFillOverlayState[bar] = nil
        barFillOverlayAnchoredTex[bar] = nil
        return
    end

    local overlay = barFillOverlay[bar]
    if not overlay then
        overlay = bar:CreateTexture(nil, "OVERLAY", nil, -8)
        overlay:SetBlendMode("BLEND")
        barFillOverlay[bar] = overlay
    end

    -- Anchor the overlay to the bar's fill texture exactly once.  SetAllPoints
    -- creates a live binding so the overlay tracks tex's width as Blizzard's
    -- SetValue resizes it, without us re-anchoring on every event.  If Blizzard
    -- ever replaces the underlying texture (SetStatusBarTexture), we re-anchor
    -- to the new tex - that's a rare event, not a per-tick one.
    if barFillOverlayAnchoredTex[bar] ~= tex then
        overlay:ClearAllPoints()
        overlay:SetAllPoints(tex)
        barFillOverlayAnchoredTex[bar] = tex
    end

    -- Skip re-colouring / re-texturing when the visible properties match the
    -- last application.  The per-event UnitFrameHealthBar_Update / ManaBar_Update
    -- hooks were re-running SetTexture+SetVertexColor on every regen tick,
    -- which is the slow flicker observed on the mana / focus bars.
    if overlay:IsShown()
        and ClassicBarFillStateMatches(barFillOverlayState[bar], mode, startColor, endColor, texturePath)
    then
        return
    end

    overlay:SetTexture(texturePath or ABP_BAR_TEX)
    if overlay.SetTexCoord then overlay:SetTexCoord(0, 1, 0, 1) end
    ClearTextureGradient(overlay)

    local r, g, b = startColor[1] or 1, startColor[2] or 1, startColor[3] or 1
    if mode == 3 then
        overlay:SetVertexColor(1, 1, 1, 1)
        ApplyGradient(overlay, startColor, endColor or startColor)
    else
        overlay:SetVertexColor(r, g, b, 1)
    end
    overlay:Show()

    barFillOverlayState[bar] = {
        mode = mode,
        texturePath = texturePath,
        startColor = { startColor[1], startColor[2], startColor[3] },
        endColor = endColor and { endColor[1], endColor[2], endColor[3] }
            or { startColor[1], startColor[2], startColor[3] },
    }
end

-- Retail's target/focus status-bar fill retains Blizzard's curved portrait-side
-- cutout even after SetStatusBarTexture.  That curve belongs under the stock round
-- portrait, but looks like a coloured wrap around the corner of ABP's square
-- portrait.  A separate texture bound to the live fill texture keeps Blizzard's
-- value/width handling while drawing an unmasked, straight right edge.
local function ApplySquareBarFillOverlay(bar, mode, startColor, endColor, texturePath)
    if ABP.isClassicClient then return end
    if not (bar and bar.GetStatusBarTexture) then return end

    local fill = bar:GetStatusBarTexture()
    if not fill then
        HideSquareBarFillOverlay(bar)
        return
    end

    local overlay = squareBarFillOverlay[bar]
    if not overlay then
        overlay = bar:CreateTexture(nil, "OVERLAY", nil, -8)
        overlay:SetBlendMode("BLEND")
        squareBarFillOverlay[bar] = overlay
    end

    if squareBarFillAnchoredTex[bar] ~= fill then
        overlay:ClearAllPoints()
        overlay:SetAllPoints(fill)
        squareBarFillAnchoredTex[bar] = fill
    end

    if overlay:IsShown()
        and ClassicBarFillStateMatches(squareBarFillState[bar], mode, startColor, endColor, texturePath)
    then
        return
    end

    overlay:SetTexture(texturePath or ABP_BAR_TEX)
    if overlay.SetTexCoord then overlay:SetTexCoord(0, 1, 0, 1) end
    ClearTextureGradient(overlay)

    local r, g, b = startColor[1] or 1, startColor[2] or 1, startColor[3] or 1
    if mode == 3 then
        overlay:SetVertexColor(1, 1, 1, 1)
        ApplyGradient(overlay, startColor, endColor or startColor)
    else
        overlay:SetVertexColor(r, g, b, 1)
    end
    overlay:Show()

    squareBarFillState[bar] = {
        mode = mode,
        texturePath = texturePath,
        startColor = { startColor[1], startColor[2], startColor[3] },
        endColor = endColor and { endColor[1], endColor[2], endColor[3] }
            or { startColor[1], startColor[2], startColor[3] },
    }
end


local function ApplyStatusBarVisual(bar, mode, startColor, endColor, useGloss, useShine, useShadow, useGlow, texturePath)
    if not (bar and bar.SetStatusBarColor) then return end
    useGloss  = useGloss and true or false
    useShine  = useShine and true or false
    useShadow = useShadow and true or false
    useGlow   = useGlow and true or false
    texturePath = texturePath or ABP_BAR_TEX

    if mode == 1 then
        barVisualState[bar] = nil
        barCustomMode[bar] = false
        HideAllBarEffects(bar)

        -- Restore texture only if we actually replaced it (Gradient mode uses WHITE8X8;
        -- Solid/Class Color keep the original Blizzard texture and never swap it).
        if barTextureReplaced[bar] then
            barTextureReplaced[bar] = nil
            if not RestoreBarOrigTexture(bar) and barOrigTexture[bar] and barOrigTexture[bar].texture then
                bar:SetStatusBarTexture(barOrigTexture[bar].texture)
            end
        end

        return
    end

    -- ── Custom mode (Solid / Gradient / Class Color) ─────────────────────────
    local prevState = barVisualState[bar]
    local needsFullSetup = not barCustomMode[bar]
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()

    -- Retail's modern bar atlases (e.g. UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health)
    -- are pre-coloured graphics, not neutral alpha masks - confirmed against
    -- Blizzard's own PlayerFrame.xml. Vertex-tinting a baked-green atlas with a
    -- class colour like Rogue yellow can only multiply the two together
    -- (green x yellow ~= a green-yellow blend), never fully override the hue.
    -- That's why "Solid"/"Class Color" looked wrong on retail even though the
    -- colour math itself was correct. Solid and Class Color need the same
    -- neutral-texture replacement Gradient already uses, but only on retail -
    -- Classic/TBC atlases really are plain masks there, and replacing the
    -- texture on those clients is what caused the old gradient-mode flicker.
    local needsNeutralTexture = (mode == 2 or mode == 3) and not ABP.isClassicClient

    if needsNeutralTexture then
        -- Retail: gradient/solid/class-color all need our controlled fill
        -- texture. Force setup if we don't have it yet, or if Blizzard reset
        -- our tile.
        if not barTextureReplaced[bar] then
            needsFullSetup = true
        else
            local currentTexture = SafeRegionValue(tex, tex and tex.GetTexture)
            if currentTexture ~= texturePath then needsFullSetup = true end
        end
    else
        -- Solid / Class Color (Classic/TBC only) AND Classic/TBC Gradient: keep
        -- the original Blizzard atlas as the bar's StatusBarTexture and let
        -- ApplyClassicBarFillOverlay paint the visible fill (gradient or solid).
        -- Replacing the texture in Classic/TBC fights Blizzard's frequent
        -- SetStatusBarTexture resets and is the source of the gradient-mode
        -- flicker on target/focus/mana bars.
        if barTextureReplaced[bar] then
            RestoreBarOrigTexture(bar)
            barTextureReplaced[bar] = nil
            tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
            needsFullSetup = true
        end
    end

    barCustomMode[bar] = true
    if needsFullSetup then
        SaveBarOrigTexture(bar)
    end

    if needsNeutralTexture then
        -- Retail only: replace with the smooth fill texture and reset atlas
        -- TexCoords so SetGradient (mode 3) renders horizontally, or so a flat
        -- SetStatusBarColor (mode 2) shows the true colour instead of tinting
        -- Blizzard's baked-in atlas colour. On Classic/TBC we never replace the
        -- bar texture (see comment above) - the overlay in
        -- ApplyClassicBarFillOverlay paints the fill instead.
        if needsFullSetup then
            bar:SetStatusBarTexture(texturePath)
            barTextureReplaced[bar] = true
            tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
            if tex then
                if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
                ClearTextureGradient(tex)
            end
        end
        -- Always enforce TexCoords while in gradient/solid/class-color mode
        -- (Blizzard resets them for critters / trivial mobs without swapping
        -- the texture back).
        if tex and tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    end
    -- Classic/TBC Solid / Class Color: keep the original Blizzard atlas texture. Its shaped
    -- alpha masks the tint to the visible bar area, so the color cannot bleed into
    -- the surrounding frame chrome the way a full WHITE8X8 rectangle would.

    local stateChanged = not BarVisualStateMatches(prevState, mode, startColor, endColor, useGloss, useShine, useShadow, useGlow, texturePath)
    -- Only clear gradients on textures we own; never touch the original atlas.
    if barTextureReplaced[bar] and tex and (needsFullSetup or stateChanged) then
        ClearTextureGradient(tex)
    end

    -- Fast path: when nothing about the requested visual has changed and we
    -- already finished initial setup, re-anchoring the gloss/shine/shadow/glow
    -- overlays each frame causes a visible flicker on non-player bars during
    -- the per-frame burst (RefreshVisibleUnitBarColors).  We still reapply the
    -- bar colour and the fill overlay so Blizzard's per-tick recolour is
    -- countered, but we skip the costly overlay rebuilds.
    local r, g, b = startColor[1], startColor[2], startColor[3]
    if not needsFullSetup and not stateChanged then
        bar:SetStatusBarColor(r, g, b, 1)
        ApplyClassicBarFillOverlay(bar, mode, startColor, endColor, texturePath)
        return
    end

    if useGloss then ApplyBarStyleOverlay(bar) else HideBarStyleOverlay(bar) end
    if useGlow then ApplyBarGlowOverlay(bar, startColor) else HideBarGlowOverlay(bar) end
    if useShadow then ApplyBarShadowOverlay(bar) else HideBarShadowOverlay(bar) end
    if useShine then ApplyBarShineOverlay(bar) else HideBarShineOverlay(bar) end

    bar:SetStatusBarColor(r, g, b, 1)
    ApplyClassicBarFillOverlay(bar, mode, startColor, endColor, texturePath)

    if mode == 3 and not ABP.isClassicClient and tex and (needsFullSetup or stateChanged) then
        -- Retail only: paint the gradient onto the bar's StatusBarTexture.
        -- On Classic/TBC the gradient is rendered by the overlay (see
        -- ApplyClassicBarFillOverlay), so we never touch the native texture.
        ApplyGradient(tex, startColor, endColor)
    end

    SaveBarVisualState(bar, mode, startColor, endColor, useGloss, useShine, useShadow, useGlow, texturePath)
end

-- Lightweight, color-only reapply of our saved custom fill colour.  Used by the
-- retail resource-bar hook below: it must NOT read any unit value (UnitPower/
-- UnitHealth are secret on retail and reading them inside a secure-call chain
-- taints execution) and must NOT rebuild the gloss/shine overlays (that caused
-- the per-frame flicker that the old OnUpdate reapply suffered).  It only re-sets
-- the StatusBarColor we already computed, so it is safe to fire every frame.
local function ReapplyBarColorFast(bar)
    local state = barVisualState[bar]
    if not state or state.mode == 1 then return end  -- only when a custom colour is active
    local s = state.startColor
    if not s then return end
    barColorReapplyGuard[bar] = true
    bar:SetStatusBarColor(s[1], s[2], s[3], 1)
    if state.mode == 3 and not ABP.isClassicClient then
        -- Gradient mode: the visible fill is a vertex gradient on the bar texture,
        -- which the flat SetStatusBarColor above replaces.  Restore the gradient so
        -- the reclamp matches the configured look instead of a flat colour.
        local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        if tex then ApplyGradient(tex, s, state.endColor or s) end
    end
    barColorReapplyGuard[bar] = false
end

-- Retail-only resource-bar recolour hook.  On retail, Blizzard repaints the
-- resource bar to its default power colour on some actions that do NOT fire a
-- UNIT_POWER event (e.g. a failed cast / "There is nothing to attack"), so our
-- event-driven reapply misses it and the bar flashes the default colour until
-- the 0.25s timer corrects it.  A post-hook on SetStatusBarColor re-asserts our
-- colour in the same frame, eliminating the flash.  hooksecurefunc is taint-safe
-- and the callback reads no secret values, so this does not risk the secret-
-- number crashes the health-bar code warns about.
local function EnsureRetailResourceColorHook(unit, bar)
    if ABP.isClassicClient then return end   -- Classic uses EnsureClassicRealtimeBarColor
    if not (unit and bar and bar.SetStatusBarColor) then return end
    barRealtimeColorUnit[bar] = unit

    local function Reapply()
        if barColorReapplyGuard[bar] or ABP.applyingBarColors then return end
        ReapplyBarColorFast(bar)
    end

    if not barRealtimeColorHooked[bar] then
        barRealtimeColorHooked[bar] = true
        if hooksecurefunc then
            pcall(hooksecurefunc, bar, "SetStatusBarColor", Reapply)
        end
    end

    -- Some Blizzard repaint paths recolour the fill directly on the bar's texture
    -- (tex:SetVertexColor / tex:SetGradient), bypassing bar:SetStatusBarColor -
    -- this is what still flashed gradient bars to the default power colour on a
    -- failed action.  Hook the current fill texture so those are caught in-frame.
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if tex and not barFillColorHooked[tex] then
        barFillColorHooked[tex] = true
        if hooksecurefunc then
            if tex.SetVertexColor then pcall(hooksecurefunc, tex, "SetVertexColor", Reapply) end
            if tex.SetGradient   then pcall(hooksecurefunc, tex, "SetGradient",   Reapply) end
        end
    end
end

local function EnsureClassicRealtimeBarColor(unit, bar)
    if not (ABP.isClassicClient and unit and bar) then return end
    barRealtimeColorUnit[bar] = unit
    if barRealtimeColorHooked[bar] then return end
    barRealtimeColorHooked[bar] = true

    local function Reapply()
        if not ABP.db or ABP.applyingBarColors then return end
        local u = barRealtimeColorUnit[bar]
        if u and UnitExists(u) then
            ABP:ApplyUnitBarColors(u)
        end
        ABP:StartBarColorBurst(0.25)
        ABP:SuppressClassicFrameFlashes()
    end

    if bar.HookScript then
        pcall(bar.HookScript, bar, "OnShow", Reapply)
    end

    if hooksecurefunc then
        pcall(hooksecurefunc, bar, "SetStatusBarColor", Reapply)
        pcall(hooksecurefunc, bar, "SetStatusBarTexture", Reapply)
    end
end

local function ApplyDefaultHealthBarColor(self, unit, bar)
    if not (unit and bar and bar.SetStatusBarColor) then return end

    if UnitHealthBar_UpdateColor then
        -- Classic/TBC builds differ on whether this reads bar.unit or a unit
        -- argument. Call it if present, then explicitly apply our computed
        -- default so the raw status bar texture never remains white.
        pcall(UnitHealthBar_UpdateColor, bar, unit)
    end

    local dr, dg, db = GetDefaultHealthColor(unit)
    bar:SetStatusBarColor(dr, dg, db, 1)
    ApplyClassicBarFillOverlay(bar, 2, { dr, dg, db }, { dr, dg, db }, GetBarTexturePath(1))
end

function ABP:ApplyUnitBarColors(unit)
    if not (self.db and unit) then return end
    if self.applyingBarColors then return end
    self.applyingBarColors = true
    local pre = UnitPrefix(unit)
    local healthBar, resourceBar = GetUnitBarFrames(unit)
    local useStraightPortraitEdge = not self.isClassicClient
        and self.supportsCustomFrameOptions
        and (pre == "target" or pre == "focus")
        and (self.db[pre.."Shape"] or 1) == 2
    barStyledResource[unit] = resourceBar or nil

    if healthBar then
        EnsureClassicRealtimeBarColor(unit, healthBar)
        local hMode  = self.db[pre.."HealthColorMode"] or 1
        local hStart = { self.db[pre.."HealthR"] or 0.0, self.db[pre.."HealthG"] or 0.85, self.db[pre.."HealthB"] or 0.15 }
        local hEnd   = { self.db[pre.."HealthER"] or 0.0, self.db[pre.."HealthEG"] or 0.45, self.db[pre.."HealthEB"] or 0.0 }
        local useGloss  = self.db[pre.."BarGloss"]
        local useShine  = self.db[pre.."BarShine"] or false
        local useShadow = self.db[pre.."BarShadow"] or false
        local useGlow   = self.db[pre.."BarGlow"] or false
        local barTexture = GetBarTexturePath(self.db[pre.."BarTexture"] or 1)
        if hMode == 4 then
            local cr, cg, cb = GetClassColor(unit)
            if cr then
                hStart = { cr, cg, cb }
                hEnd   = { DarkenColor(cr, cg, cb) }
            end
            hMode = 2  -- render as solid using class color
        end
        if useGloss == nil then useGloss = true end
        ApplyStatusBarVisual(healthBar, hMode, hStart, hEnd, useGloss, useShine, useShadow, useGlow, barTexture)
        -- After restoring Default, immediately apply Blizzard's health colour
        -- so the bar never sits on plain white.
        if hMode == 1 then
            ApplyDefaultHealthBarColor(self, unit, healthBar)
        end
        if useStraightPortraitEdge then
            if hMode == 1 then
                local dr, dg, db = GetDefaultHealthColor(unit)
                ApplySquareBarFillOverlay(healthBar, 2, { dr, dg, db }, { dr, dg, db }, barTexture)
            else
                ApplySquareBarFillOverlay(healthBar, hMode, hStart, hEnd, barTexture)
            end
        else
            HideSquareBarFillOverlay(healthBar)
        end
    end

    if resourceBar then
        EnsureClassicRealtimeBarColor(unit, resourceBar)
        EnsureRetailResourceColorHook(unit, resourceBar)
        local rMode  = self.db[pre.."ResourceColorMode"] or 1
        local rStart = { self.db[pre.."ResourceR"] or 0.0, self.db[pre.."ResourceG"] or 0.55, self.db[pre.."ResourceB"] or 1.0 }
        local rEnd   = { self.db[pre.."ResourceER"] or 0.0, self.db[pre.."ResourceEG"] or 0.25, self.db[pre.."ResourceEB"] or 0.85 }
        local useGloss  = self.db[pre.."BarGloss"]
        local useShine  = self.db[pre.."BarShine"] or false
        local useShadow = self.db[pre.."BarShadow"] or false
        local useGlow   = self.db[pre.."BarGlow"] or false
        local barTexture = GetBarTexturePath(self.db[pre.."BarTexture"] or 1)
        if rMode == 4 then
            local cr, cg, cb = GetClassColor(unit)
            if cr then
                rStart = { cr, cg, cb }
                rEnd   = { DarkenColor(cr, cg, cb) }
            end
            rMode = 2  -- render as solid using class color
        end
        if useGloss == nil then useGloss = true end
        ApplyStatusBarVisual(resourceBar, rMode, rStart, rEnd, useGloss, useShine, useShadow, useGlow, barTexture)
        -- After restoring Default on resource bar, apply the correct power colour
        -- immediately (UnitHealthBar_UpdateColor is health-only, so we use the
        -- power-type colour directly).
        if rMode == 1 then
            local dr, dg, db = GetDefaultResourceColor(unit)
            resourceBar:SetStatusBarColor(dr, dg, db, 1)
            ApplyClassicBarFillOverlay(resourceBar, 2, { dr, dg, db }, { dr, dg, db }, barTexture)
        end
        if useStraightPortraitEdge then
            if rMode == 1 then
                local dr, dg, db = GetDefaultResourceColor(unit)
                ApplySquareBarFillOverlay(resourceBar, 2, { dr, dg, db }, { dr, dg, db }, barTexture)
            else
                ApplySquareBarFillOverlay(resourceBar, rMode, rStart, rEnd, barTexture)
            end
        else
            HideSquareBarFillOverlay(resourceBar)
        end
    end
    self.applyingBarColors = false
end

-- Per-frame colour-only re-clamp of visible resource bars, driven by the post-
-- action burst in OnUpdate.  Reproduces the frequent re-apply that UNIT_POWER
-- events provide while a target is present, so a failed action cannot leave the
-- resource bar flashed to its default colour.  Resource bar + colour only: it
-- reads no unit values (no secret-number taint) and rebuilds no overlays.
function ABP:BurstReclampBars()
    if self.isClassicClient then return end
    -- Use the resource bars we actually styled (cached in ApplyUnitBarColors) so we
    -- reclamp the exact same objects our colour state is keyed on, and avoid the
    -- cost of re-resolving the frame hierarchy every frame during the burst.
    for _, bar in pairs(barStyledResource) do
        if bar then ReapplyBarColorFast(bar) end
    end
end

function ABP:RefreshAllBarColors()
    self:ApplyUnitBarColors("player")
    self:ApplyUnitBarColors("pet")
    self:ApplyUnitBarColors("target")
    self:ApplyUnitBarColors("focus")
    for i = 1, 4 do
        self:ApplyUnitBarColors("party"..i)
    end
end

function ABP:RefreshVisibleUnitBarColors()
    if PlayerFrame and PlayerFrame:IsShown() then self:ApplyUnitBarColors("player") end
    if PetFrame and PetFrame:IsShown() then self:ApplyUnitBarColors("pet") end
    if TargetFrame and TargetFrame:IsShown() then self:ApplyUnitBarColors("target") end
    if FocusFrame and FocusFrame:IsShown() then self:ApplyUnitBarColors("focus") end
    for i = 1, 4 do
        local frame = _G["PartyMemberFrame"..i]
        if frame and frame:IsShown() then
            self:ApplyUnitBarColors("party"..i)
        end
    end
end

-------------------------------------------------------------------------------
-- Name highlight / text colours
-------------------------------------------------------------------------------
local nameStyleOrig = {}
local knownNameHighlights = setmetatable({}, { __mode = "k" })
local nameHighlightOverlays = setmetatable({}, { __mode = "k" })
local syntheticNameHighlights = setmetatable({}, { __mode = "k" })

local function GetFrameRegions(frame)
    if not (frame and frame.GetRegions) then return nil end
    if frame.IsForbidden and frame:IsForbidden() then return nil end
    local ok, regions = pcall(function() return { frame:GetRegions() } end)
    if ok then return regions end
end

-- Midnight/retail secure-execution scope can return "secret" tainted strings
-- from Blizzard getters like GetAtlas / GetName on certain frames (e.g.
-- TargetFrameSpellBar children).  Any string method call on a secret value
-- ("foo":lower(), find, etc.) throws "attempt to index a secret string value".
-- This helper returns "" for nil, non-strings, and secret-tainted strings,
-- so downstream find/lower calls always operate on a real string.
local _isecstr = type(issecretvalue) == "function" and issecretvalue or nil
local function SafeLowerString(getter, obj)
    if not (obj and getter) then return "" end
    local ok, value = pcall(getter, obj)
    if not ok or type(value) ~= "string" then return "" end
    if _isecstr and _isecstr(value) then return "" end
    local lower_ok, lower_value = pcall(string.lower, value)
    if not lower_ok or type(lower_value) ~= "string" then return "" end
    return lower_value
end

local function IsForbiddenNameStyleRegion(region)
    if not region then return true end
    if region.IsForbidden and region:IsForbidden() then return true end
    if knownNameHighlights[region] then return false end
    local name = SafeLowerString(region.GetName, region)
    local parent = region.GetParent and region:GetParent() or nil
    local parentName = SafeLowerString(parent and parent.GetName, parent)
    local atlas = SafeLowerString(region.GetAtlas, region)

    local function HasBlockedToken(text)
        return text:find("health", 1, true)
            or text:find("mana", 1, true)
            or text:find("power", 1, true)
            or text:find("resource", 1, true)
            or text:find("status", 1, true)
            or text:find("portrait", 1, true)
            or text:find("rest", 1, true)
            or text:find("combat", 1, true)
            or text:find("flash", 1, true)
    end

    return HasBlockedToken(name) or HasBlockedToken(parentName) or HasBlockedToken(atlas)
end

local function IsNameHighlightTexture(region)
    if not (region and region.GetObjectType and region:GetObjectType() == "Texture") then return false end
    if IsForbiddenNameStyleRegion(region) then return false end
    local name = SafeLowerString(region.GetName, region)
    return name:find("name", 1, true)
        and (name:find("background", 1, true) or name:find("bg", 1, true))
end

local function FindRegionRecursive(root, wantKind, depth, seen)
    if not root or (depth and depth < 0) then return nil end
    if root.IsForbidden and root:IsForbidden() then return nil end
    seen = seen or {}
    if seen[root] then return nil end
    seen[root] = true

    local regions = GetFrameRegions(root)
    if regions then
        for _, region in ipairs(regions) do
            if region then
                local objectType = region.GetObjectType and region:GetObjectType()
                local name = SafeLowerString(region.GetName, region)
                if wantKind == "name" then
                    if objectType == "FontString" and name:find("name", 1, true) then
                        return region
                    end
                elseif wantKind == "level" then
                    if objectType == "FontString" and name:find("level", 1, true) then
                        return region
                    end
                elseif IsNameHighlightTexture(region) then
                    return region
                end
            end
        end
    end

    if root.GetChildren then
        local ok, children = pcall(function() return { root:GetChildren() } end)
        if not ok then return nil end
        for _, child in ipairs(children) do
            local name = SafeLowerString(child.GetName, child)
            if not (child.IsForbidden and child:IsForbidden())
                and not name:find("cast", 1, true) and not name:find("spell", 1, true)
                and not name:find("aura", 1, true) and not name:find("buff", 1, true) then
                local found = FindRegionRecursive(child, wantKind, (depth or 4) - 1, seen)
                if found then return found end
            end
        end
    end
    return nil
end

local function FindFirstRegion(...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if type(region) == "function" then region = region() end
        if region then return region end
    end
end

local function AddUniqueRegion(list, region)
    if not region or IsForbiddenNameStyleRegion(region) then return end
    for _, existing in ipairs(list) do
        if existing == region then return end
    end
    list[#list + 1] = region
end

local function IsSafeNameStyleScanChild(frame)
    if not (frame and frame.GetName) then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    local name = SafeLowerString(frame.GetName, frame)
    -- unnamed anonymous frames are layout containers and safe to scan;
    -- dangerous frames (CastingBar, BuffFrame, etc.) always have explicit names
    if name == "" then return true end
    if name:find("spell", 1, true)
        or name:find("cast", 1, true)
        or name:find("buff", 1, true)
        or name:find("debuff", 1, true)
        or name:find("aura", 1, true) then
        return false
    end
    return name:find("texture", 1, true)
        or name:find("content", 1, true)
        or name:find("main", 1, true)
        or name:find("targetframe", 1, true)
        or name:find("playerframe", 1, true)
        or name:find("party", 1, true)
end

local function CollectNamedHighlightRegions(root, list, depth, seen)
    if not root or (depth and depth < 0) then return end
    if root.IsForbidden and root:IsForbidden() then return end
    seen = seen or {}
    if seen[root] then return end
    seen[root] = true

    local regions = GetFrameRegions(root)
    if regions then
        for _, region in ipairs(regions) do
            if IsNameHighlightTexture(region) then
                AddUniqueRegion(list, region)
            end
        end
    end

    if root.GetChildren then
        local ok, children = pcall(function() return { root:GetChildren() } end)
        if not ok then return end
        for _, child in ipairs(children) do
            if IsSafeNameStyleScanChild(child) then
                CollectNamedHighlightRegions(child, list, (depth or 4) - 1, seen)
            end
        end
    end
end

local function GetPartyFrameForName(unit)
    local idx = PartyIndexFromUnit(unit)
    if not idx then return nil end
    return ResolvePath(_G.PartyFrame, "MemberFrame"..idx) or GetPartyRootFrame(idx)
end

local function GetUnitNameRegions(unit)
    local root
    local nameText
    local levelText
    local levelCircle
    local highlights = {}

    -- Retail's red/yellow/green name band is ReputationColor, not NameBackground.
    -- Its atlas includes "PortraitOn", so generic portrait filtering rejected it.
    -- Prefer these exact widgets and avoid evaluating recursive fallbacks eagerly.
    if unit == "target" or unit == "focus" then
        local frame = unit == "target" and TargetFrame or FocusFrame
        local main = ResolvePath(frame, "TargetFrameContent", "TargetFrameContentMain")
        if main and main.Name then
            local highlight = main.ReputationColor or main.NameBackground
            if highlight then
                knownNameHighlights[highlight] = true
                AddUniqueRegion(highlights, highlight)
            end
            return main.Name, main.LevelText, highlights, main.LevelBackgroundCircle
        end
    end

    if unit == "player" then
        root = PlayerFrame
        nameText = FindFirstRegion(
                _G.PlayerFrameTextureFrameName,
                _G.PlayerName,
                _G.PlayerFrameName,
                PlayerFrame and PlayerFrame.Name,
                ResolvePath(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain", "Name"),
                function() return FindRegionRecursive(PlayerFrame, "name", 5) end)
        levelText = FindFirstRegion(
                _G.PlayerFrameTextureFrameLevelText,
                _G.PlayerLevelText,
                PlayerFrame and PlayerFrame.LevelText,
                ResolvePath(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain", "LevelText"),
                function() return FindRegionRecursive(PlayerFrame, "level", 5) end)
        levelCircle = FindFirstRegion(
                PlayerFrame and PlayerFrame.LevelBackgroundCircle,
                ResolvePath(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain", "LevelBackgroundCircle"),
                function() return FindRegionRecursive(PlayerFrame, "levelbackgroundcircle", 5) end)
        AddUniqueRegion(highlights, FindFirstRegion(
                _G.PlayerFrameNameBackground,
                _G.PlayerNameBackground,
                PlayerFrame and PlayerFrame.NameBackground,
                ResolvePath(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain", "NameBackground"),
                function() return FindRegionRecursive(PlayerFrame, "highlight", 5) end))
    elseif unit == "pet" then
        root = PetFrame
        nameText = FindFirstRegion(
                _G.PetName,
                _G.PetFrameName,
                PetFrame and PetFrame.Name,
                ResolvePath(PetFrame, "PetFrameContent", "PetFrameContentMain", "Name"),
                function() return FindRegionRecursive(PetFrame, "name", 5) end)
        levelText = FindFirstRegion(
                _G.PetLevelText,
                PetFrame and PetFrame.LevelText,
                ResolvePath(PetFrame, "PetFrameContent", "PetFrameContentMain", "LevelText"),
                function() return FindRegionRecursive(PetFrame, "level", 5) end)
        levelCircle = FindFirstRegion(
                PetFrame and PetFrame.LevelBackgroundCircle,
                ResolvePath(PetFrame, "PetFrameContent", "PetFrameContentMain", "LevelBackgroundCircle"),
                function() return FindRegionRecursive(PetFrame, "levelbackgroundcircle", 5) end)
        AddUniqueRegion(highlights, FindFirstRegion(
                _G.PetFrameNameBackground,
                PetFrame and PetFrame.NameBackground,
                ResolvePath(PetFrame, "PetFrameContent", "PetFrameContentMain", "NameBackground"),
                function() return FindRegionRecursive(PetFrame, "highlight", 5) end))
    elseif unit == "target" then
        root = TargetFrame
        nameText = FindFirstRegion(
                _G.TargetFrameTextureFrameName,
                _G.TargetFrameName,
                ResolvePath(TargetFrame, "TargetFrameContent", "TargetFrameContentMain", "Name"),
                function() return FindRegionRecursive(TargetFrame, "name", 5) end)
        levelText = FindFirstRegion(
                _G.TargetFrameTextureFrameLevelText,
                _G.TargetFrameLevelText,
                ResolvePath(TargetFrame, "TargetFrameContent", "TargetFrameContentMain", "LevelText"),
                function() return FindRegionRecursive(TargetFrame, "level", 5) end)
        levelCircle = FindFirstRegion(
                ResolvePath(TargetFrame, "TargetFrameContent", "TargetFrameContentMain", "LevelBackgroundCircle"),
                function() return FindRegionRecursive(TargetFrame, "levelbackgroundcircle", 5) end)
        AddUniqueRegion(highlights, FindFirstRegion(
                _G.TargetFrameNameBackground,
                ResolvePath(TargetFrame, "TargetFrameContent", "TargetFrameContentMain", "NameBackground"),
                function() return FindRegionRecursive(TargetFrame, "highlight", 5) end))
    elseif unit == "focus" then
        root = FocusFrame
        nameText = FindFirstRegion(
                _G.FocusFrameTextureFrameName,
                _G.FocusFrameName,
                ResolvePath(FocusFrame, "TargetFrameContent", "TargetFrameContentMain", "Name"),
                function() return FindRegionRecursive(FocusFrame, "name", 5) end)
        levelText = FindFirstRegion(
                _G.FocusFrameTextureFrameLevelText,
                _G.FocusFrameLevelText,
                ResolvePath(FocusFrame, "TargetFrameContent", "TargetFrameContentMain", "LevelText"),
                function() return FindRegionRecursive(FocusFrame, "level", 5) end)
        levelCircle = FindFirstRegion(
                ResolvePath(FocusFrame, "TargetFrameContent", "TargetFrameContentMain", "LevelBackgroundCircle"),
                function() return FindRegionRecursive(FocusFrame, "levelbackgroundcircle", 5) end)
        AddUniqueRegion(highlights, FindFirstRegion(
                _G.FocusFrameNameBackground,
                ResolvePath(FocusFrame, "TargetFrameContent", "TargetFrameContentMain", "NameBackground"),
                function() return FindRegionRecursive(FocusFrame, "highlight", 5) end))
    else
        root = GetPartyFrameForName(unit)
        local idx = PartyIndexFromUnit(unit)
        nameText = FindFirstRegion(
                idx and _G["PartyMemberFrame"..idx.."Name"],
                root and root.Name,
                ResolvePath(root, "PartyMemberFrameContent", "PartyMemberFrameContentMain", "Name"),
                ResolvePath(root, "PartyFrameContent", "PartyFrameContentMain", "Name"),
                function() return FindRegionRecursive(root, "name", 5) end)
        levelText = FindFirstRegion(
                idx and _G["PartyMemberFrame"..idx.."LevelText"],
                root and root.LevelText,
                ResolvePath(root, "PartyMemberFrameContent", "PartyMemberFrameContentMain", "LevelText"),
                ResolvePath(root, "PartyFrameContent", "PartyFrameContentMain", "LevelText"),
                function() return FindRegionRecursive(root, "level", 5) end)
        levelCircle = FindFirstRegion(
                idx and _G["PartyMemberFrame"..idx.."LevelBackgroundCircle"],
                root and root.LevelBackgroundCircle,
                ResolvePath(root, "PartyMemberFrameContent", "PartyMemberFrameContentMain", "LevelBackgroundCircle"),
                ResolvePath(root, "PartyFrameContent", "PartyFrameContentMain", "LevelBackgroundCircle"),
                function() return FindRegionRecursive(root, "levelbackgroundcircle", 5) end)
        AddUniqueRegion(highlights, FindFirstRegion(
                idx and _G["PartyMemberFrame"..idx.."NameBackground"],
                root and root.NameBackground,
                ResolvePath(root, "PartyMemberFrameContent", "PartyMemberFrameContentMain", "NameBackground"),
                ResolvePath(root, "PartyFrameContent", "PartyFrameContentMain", "NameBackground"),
                function() return FindRegionRecursive(root, "highlight", 5) end))
    end

    if #highlights == 0 then CollectNamedHighlightRegions(root, highlights, 5) end
    -- Never infer name backgrounds just from proximity: that can select other
    -- unit-frame artwork when the real band is absent or restricted.

    return nameText, levelText, highlights, levelCircle
end

local function SaveNameRegionOrig(region)
    if not region or nameStyleOrig[region] then return end
    local r, g, b, a = 1, 1, 1, 1
    if region.GetTextColor then
        r, g, b, a = region:GetTextColor()
    elseif region.GetVertexColor then
        r, g, b, a = region:GetVertexColor()
    end
    local components = { r, g, b, a }
    for i = 1, 4 do
        local value = components[i]
        if (issecretvalue and issecretvalue(value)) or type(value) ~= "number" then components[i] = 1 end
    end
    nameStyleOrig[region] = { r = components[1], g = components[2], b = components[3], a = components[4] }
end

local function RestoreNameRegion(region)
    local orig = region and nameStyleOrig[region]
    if not orig then return end
    if region.SetTextColor then
        region:SetTextColor(orig.r, orig.g, orig.b, orig.a)
    elseif region.SetVertexColor then
        region:SetVertexColor(orig.r, orig.g, orig.b, orig.a)
    end
end

-- LevelBackgroundCircle / LevelText sit in Blizzard's default LOW strata, so
-- the animated portrait (UNIT_ART_STRATA = MEDIUM) renders on top of them,
-- hiding the level badge behind the portrait. Reparenting them onto a small
-- MEDIUM-strata wrapper frame fixes the stacking without moving them - a
-- reparent doesn't break Blizzard's own self.LevelText references, since
-- that's just a table field pointing at the same object regardless of its
-- visual parent, and SetPoint anchors keep pointing at the same frames too.
local function RaiseLevelBadge(circle, text)
    if InCombatLockdown and InCombatLockdown() then return end
    -- Not every frame has both: Blizzard's real TargetFrame.xml only defines
    -- LevelText, no LevelBackgroundCircle at all (that's Player-frame-only).
    -- Requiring both to be non-nil meant target's LevelText never got raised.
    -- Raise whichever of the two actually exists.
    local anchor = circle or text
    if not anchor then return end
    local wrap = anchor._abpLevelWrap
    if not wrap then
        wrap = CreateFrame("Frame", nil, anchor:GetParent())
        wrap:SetAllPoints(anchor:GetParent())
        anchor._abpLevelWrap = wrap
    end
    -- MEDIUM-strata + a higher frame level (SetUnitOverlayLayer) put the level
    -- text above Blizzard's ordinary 2D chrome, and that alone was enough on
    -- the player frame - but on target it still rendered behind the portrait.
    -- The animated portrait is a 3D ModelScene, and those appear to composite
    -- above ordinary same-strata 2D frames independent of frame-level math in
    -- at least some cases. HIGH strata beats MEDIUM unconditionally regardless
    -- of any of that, so use it here instead of chasing frame-level numbers.
    wrap:SetFrameStrata("HIGH")
    if circle and circle:GetParent() ~= wrap then circle:SetParent(wrap) end
    if text and text:GetParent() ~= wrap then text:SetParent(wrap) end
end

local targetHeaderLayout = {}

local function LayoutTargetHeader(self, unit, nameText, levelText)
    if not self.supportsCustomFrameOptions or (unit ~= "target" and unit ~= "focus") then return end
    -- These are known Blizzard widgets, not a recursive scan of protected
    -- descendants. No health/status values are read or used to decide visibility.
    local root = unit == "target" and TargetFrame or FocusFrame
    local main = ResolvePath(root, "TargetFrameContent", "TargetFrameContentMain")
    local healthBar = main and main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
    if not (main and nameText and nameText == main.Name and healthBar) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local previous = targetHeaderLayout[nameText]
    if previous and previous.bar == healthBar and previous.level == levelText then return end

    -- A full rectangular custom fill no longer has Blizzard's shaped name band.
    -- Keep the header above the live health bar instead of sharing its interior
    -- with DeadText/UnconsciousText. Relative anchors also follow classification
    -- changes and frame movement without reading secret screen coordinates.
    nameText:ClearAllPoints()
    nameText:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", 18, 2)
    if levelText and levelText == main.LevelText then
        levelText:ClearAllPoints()
        levelText:SetPoint("BOTTOMRIGHT", nameText, "BOTTOMLEFT", -4, 0)
    end
    targetHeaderLayout[nameText] = { bar = healthBar, level = levelText }
end

local function EnsureSyntheticNameHighlight(unit, nameText, levelText, highlights)
    if #highlights > 0 or not nameText then return end
    local texture = syntheticNameHighlights[nameText]
    if not texture and not (InCombatLockdown and InCombatLockdown()) then
        local parent = nameText.GetParent and nameText:GetParent()
        if parent and parent.CreateTexture then
            texture = parent:CreateTexture(nil, "BACKGROUND", nil, 0)
            texture:SetColorTexture(0, 0, 0, 0)
            if unit == "player" then
                texture:SetPoint("TOPLEFT", nameText, "TOPLEFT", -2, 2)
                texture:SetPoint("BOTTOMRIGHT", levelText or nameText, "BOTTOMRIGHT", 2, -2)
            else
                texture:SetPoint("TOPLEFT", levelText or nameText, "TOPLEFT", -2, 2)
                texture:SetPoint("BOTTOMRIGHT", nameText, "BOTTOMRIGHT", 2, -2)
            end
            syntheticNameHighlights[nameText] = texture
            knownNameHighlights[texture] = true
        end
    end
    if texture then highlights[#highlights + 1] = texture end
end

function ABP:ApplyUnitNameStyle(unit)
    if not (self.db and unit) then return end
    local pre = UnitPrefix(unit)
    local nameText, levelText, highlights, levelCircle = GetUnitNameRegions(unit)
    RaiseLevelBadge(levelCircle, levelText)
    LayoutTargetHeader(self, unit, nameText, levelText)
    EnsureSyntheticNameHighlight(unit, nameText, levelText, highlights)

    local mode = self.db[pre.."NameHighlightMode"] or 1
    for _, highlight in ipairs(highlights or {}) do
        if not IsForbiddenNameStyleRegion(highlight) then
            if mode == 1 then
                -- Native faction colors/visibility stay under Blizzard's control.
                SetNativeTextureHidden(highlight, false)
                if nameHighlightOverlays[highlight] then nameHighlightOverlays[highlight]:Hide() end
            else
                SetNativeTextureHidden(highlight, true)
                local a = self.db[pre.."NameHighlightA"]
                if a == nil then a = 0.45 end
                local overlay = nameHighlightOverlays[highlight]
                if mode == 2 then
                    if overlay then overlay:Hide() end
                else
                    -- Paint an addon-owned neutral texture, rather than tinting
                    -- faction artwork which Blizzard recolors on every target update.
                    if not overlay and not (InCombatLockdown and InCombatLockdown()) then
                        local parent = highlight.GetParent and highlight:GetParent()
                        if parent and parent.CreateTexture then
                            overlay = parent:CreateTexture(nil, "BACKGROUND", nil, 0)
                            overlay:SetAllPoints(highlight)
                            nameHighlightOverlays[highlight] = overlay
                        end
                    end
                    if overlay then
                        local r = self.db[pre.."NameHighlightR"] or 0
                        local g = self.db[pre.."NameHighlightG"] or 0
                        local b = self.db[pre.."NameHighlightB"] or 0
                        if mode == 3 then
                            local cr, cg, cb = GetClassColor(unit)
                            r, g, b = cr or 0, cg or 0, cb or 0
                        end
                        overlay:SetColorTexture(r, g, b, a)
                        overlay:Show()
                    end
                end
            end
        end
    end

    local function ApplyTextColor(fontString)
        if not fontString then return end
        SaveNameRegionOrig(fontString)
        local mode = self.db[pre.."NameTextMode"] or 1
        if mode == 1 then
            RestoreNameRegion(fontString)
        else
            local r, g, b = self.db[pre.."NameTextR"] or 0.82, self.db[pre.."NameTextG"] or 0.85, self.db[pre.."NameTextB"] or 0.90
            if mode == 3 then
                local cr, cg, cb = GetClassColor(unit)
                if cr then r, g, b = cr, cg, cb end
            end
            if fontString.SetTextColor then fontString:SetTextColor(r, g, b, 1) end
        end
    end

    ApplyTextColor(nameText)
    ApplyTextColor(levelText)
end

function ABP:RefreshAllNameStyles()
    self:ApplyUnitNameStyle("player")
    self:ApplyUnitNameStyle("pet")
    self:ApplyUnitNameStyle("target")
    self:ApplyUnitNameStyle("focus")
    for i = 1, 4 do
        self:ApplyUnitNameStyle("party"..i)
    end
end

function ABP:RefreshVisibleUnitNameStyles()
    if PlayerFrame and PlayerFrame:IsShown() then self:ApplyUnitNameStyle("player") end
    if PetFrame and PetFrame:IsShown() then self:ApplyUnitNameStyle("pet") end
    if TargetFrame and TargetFrame:IsShown() then self:ApplyUnitNameStyle("target") end
    if FocusFrame and FocusFrame:IsShown() then self:ApplyUnitNameStyle("focus") end
    for i = 1, 4 do
        local frame = GetPartyRootFrame(i)
        if frame and frame:IsShown() then
            self:ApplyUnitNameStyle("party"..i)
        end
    end
end


-------------------------------------------------------------------------------
-- Emblem hide / restore
-- Exact TWW field paths confirmed from Blizzard FrameXML source:
--   player → PlayerFrameContent.PlayerFrameContentContextual  {PVPIcon, PrestigePortrait, PrestigeBadge}
--   target → TargetFrameContent.TargetFrameContentContextual  {PvpIcon, PrestigePortrait, PrestigeBadge}
--   focus  → TargetFrameContent.TargetFrameContentContextual  {PvpIcon, PrestigePortrait, PrestigeBadge}
--   party  → PartyMemberOverlay                               {PVPIcon}
-- Note: target/focus use "PvpIcon" (mixed-case), player uses "PVPIcon" (all-caps).
-------------------------------------------------------------------------------
local PLAYER_EMBLEM_KEYS = { "PVPIcon", "PrestigePortrait", "PrestigeBadge" }
local TARGET_EMBLEM_KEYS = { "PvpIcon", "PrestigePortrait", "PrestigeBadge" }
local PARTY_EMBLEM_KEYS  = { "PVPIcon" }

local function GetEmblemCtxAndKeys(unit)
    if unit == "player" then
        local pfc = PlayerFrame and PlayerFrame.PlayerFrameContent
        return pfc and pfc.PlayerFrameContentContextual, PLAYER_EMBLEM_KEYS
    elseif unit == "target" then
        local tfc = TargetFrame and TargetFrame.TargetFrameContent
        return tfc and tfc.TargetFrameContentContextual, TARGET_EMBLEM_KEYS
    elseif unit == "focus" then
        local ffc = FocusFrame and FocusFrame.TargetFrameContent
        return ffc and ffc.TargetFrameContentContextual, TARGET_EMBLEM_KEYS
    end
    return nil, nil
end

-- Called when the small player portrait-icons toggle changes or after Blizzard
-- refreshes the tiny tank/heal/dps icon.
function ABP:FlushRoleIconHide()
    if not self.db then return end
    if self.isClassicClient then return end

    local ctx = PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual
    local roleIcon = ctx and ctx.RoleIcon
    if not roleIcon then return end

    SetNativeTextureHidden(roleIcon, self.db.playerHideRoleIcon)
end

-- Called when the small player portrait-icons toggle changes or after Blizzard
-- refreshes the lower-right corner embellishment.
function ABP:FlushCornerIconHide()
    if not self.db then return end
    if self.isClassicClient then return end

    local ctx = PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual
    local cornerIcon = ctx and ctx.PlayerPortraitCornerIcon
    if not cornerIcon then return end

    SetNativeTextureHidden(cornerIcon, self.db.playerHideRoleIcon)
end

function ABP:FlushStatusGlowHide()
    if not self.db or self.isClassicClient then return end
    local statusTex = PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.StatusTexture
    SetNativeStatusGlowHidden(statusTex, self.db.playerHideStatusGlow or false)
end

-- Rested indicator controls only the ZZZ animation. Status glow is separate.
-- ZZZ: PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerRestLoop
function ABP:FlushRestedHide()
    if not self.db then return end
    if self.isClassicClient then return end
    local hide = self.db.playerHideRested or false

    -- ---- ZZZ animation (PlayerRestLoop) ------------------------------------
    local restLoop = PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerRestLoop
    if restLoop then
        if hide then
            restLoop:Hide()
            if restLoop.PlayerRestLoopAnim then restLoop.PlayerRestLoopAnim:Stop() end
        else
            -- Only restore if the player is actually resting; let Blizzard decide.
            if PlayerFrame_UpdatePlayerRestLoop and IsResting then
                PlayerFrame_UpdatePlayerRestLoop(IsResting())
            end
        end
    end

    -- Reapply the independent status setting without inheriting the ZZZ setting.
    self:FlushStatusGlowHide()
end

function ABP:ApplyPlayerCombatTextSetting()
    if not self.db then return end
    if self.isClassicClient then return end
    local show = self.db.playerShowCombatText ~= false
    for _, item in ipairs(self.playerCombatTextItems or {}) do
        if item.kind == "strata" then
            if show then
                SetUnitOverlayLayer(item.frame)
                item.frame:Show()
            else
                -- Install a one-time hook so Blizzard can't re-show it while suppressed.
                if not item._abpHook then
                    item._abpHook = true
                    item.frame:HookScript("OnShow", function(f)
                        if ABP.db and ABP.db.playerShowCombatText == false then
                            f:Hide()
                        end
                    end)
                end
                item.frame:Hide()
            end
        elseif item.kind == "wrap" then
            if show then item.frame:Show() else item.frame:Hide() end
        end
    end
end

-- Called when the Hide Emblem toggle changes or after Blizzard's PvP-status update fires.
function ABP:FlushEmblemHide(unit)
    if not self.db then return end
    if self.isClassicClient then return end
    local pre  = UnitPrefix(unit)
    local hide = self.db[pre.."HideEmblem"] or false

    local function ApplyCtx(ctx, keys)
        if not ctx or not keys then return end
        for _, key in ipairs(keys) do
            local tex = ctx[key]
            SetNativeTextureHidden(tex, hide)
        end
    end

    if unit == "party" then
        for i = 1, 4 do
            local uf = _G["PartyMemberFrame"..i]
            ApplyCtx(uf and uf.PartyMemberOverlay, PARTY_EMBLEM_KEYS)
        end
        return
    end

    local ctx, keys = GetEmblemCtxAndKeys(unit)
    ApplyCtx(ctx, keys)
end

function ABP:RefreshNativeIconVisibility()
    if not self.db or self.isClassicClient then return end
    self:FlushEmblemHide("player")
    self:FlushEmblemHide("target")
    self:FlushEmblemHide("focus")
    self:FlushEmblemHide("party")
    self:FlushRoleIconHide()
    self:FlushCornerIconHide()
    self:UpdateBlizzardClassPowerVisibility()
    self:FlushStatusGlowHide()
end

-------------------------------------------------------------------------------
-- Profile system
-- Profiles are stored in AnimatedBlizzPortraitDB.profiles[name] as a flat copy
-- of every settings key.  Because SavedVariables is per-account all characters
-- on the same account share the same profile list automatically.
-------------------------------------------------------------------------------
function ABP:SaveProfile(name)
    if not name or name:match("^%s*$") then return nil end
    name = name:match("^%s*(.-)%s*$")   -- trim leading/trailing whitespace
    if not self.db.profiles then self.db.profiles = {} end
    local snapshot = {}
    for k in pairs(DEFAULTS) do
        if k ~= "profiles" then
            snapshot[k] = self.db[k]
        end
    end
    self.db.profiles[name] = snapshot
    return name
end

function ABP:LoadProfile(name)
    if not (self.db.profiles and self.db.profiles[name]) then return false end
    local profile = self.db.profiles[name]
    for k in pairs(DEFAULTS) do
        if k ~= "profiles" and profile[k] ~= nil then
            self.db[k] = profile[k]
        end
    end
    self:RefreshAll()
    self:ApplySettingsAppearance()
    return true
end

function ABP:DeleteProfile(name)
    if self.db.profiles then
        self.db.profiles[name] = nil
    end
end

function ABP:GetProfileNames()
    local names = {}
    if self.db.profiles then
        for name in pairs(self.db.profiles) do
            names[#names + 1] = name
        end
        table.sort(names)
    end
    return names
end

-------------------------------------------------------------------------------
-- Returns a border colour for an NPC's threat classification.
local function GetClassificationBorderColor(unit)
    if not (UnitClassification and UnitExists and UnitExists(unit)) then return 0,0,0,0 end
    local c = UnitClassification(unit)
    if     c == "worldboss"  then return 1.00, 0.15, 0.00, 1  -- fiery red-orange
    elseif c == "elite"      then return 0.82, 0.85, 0.90, 1  -- steel silver
    elseif c == "rareelite"  then return 0.70, 0.20, 1.00, 1  -- purple
    elseif c == "rare"       then return 0.40, 0.80, 1.00, 1  -- steel blue
    end
    return 0, 0, 0, 0
end

-- Border colour
-------------------------------------------------------------------------------
function ABP:ApplyBorderColor(p, unit)
    local db  = self.db
    local pre = UnitPrefix(unit)
    local borderSize = math.max(0, math.min(12, db[pre.."BorderSize"] or 2))
    local edgeSize = math.max(1, borderSize)

    if p.borderT then p.borderT:SetHeight(edgeSize) end
    if p.borderB then p.borderB:SetHeight(edgeSize) end
    if p.borderL then p.borderL:SetWidth(edgeSize) end
    if p.borderR then p.borderR:SetWidth(edgeSize) end

    if not self.supportsCustomFrameOptions then
        p.borderT:SetColorTexture(0, 0, 0, 0)
        p.borderB:SetColorTexture(0, 0, 0, 0)
        p.borderL:SetColorTexture(0, 0, 0, 0)
        p.borderR:SetColorTexture(0, 0, 0, 0)
        return
    end

    local bc  = db[pre.."BorderC"] or 1
    local r, g, b, a = 0.86, 0.90, 0.95, 1

    if borderSize == 0 or bc == 1 then      -- Transparent
        a = 0
    elseif bc == 2 then  -- Slate
        r, g, b = 0.22, 0.31, 0.40
    elseif bc == 3 then  -- Silver
        r, g, b = 0.75, 0.75, 0.75
    elseif bc == 4 then  -- Class Color
        local classFile = select(2, UnitClass(unit))
        local c = not (issecretvalue and issecretvalue(classFile)) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if c then r, g, b = c.r, c.g, c.b else r, g, b = 0, 0, 0 end
    else                 -- Custom (bc == 5)
        r = db[pre.."BorderR"] or 0.82
        g = db[pre.."BorderG"] or 0.85
        b = db[pre.."BorderB"] or 0.90
    end

    p.borderT:SetColorTexture(r, g, b, a)
    p.borderB:SetColorTexture(r, g, b, a)
    p.borderL:SetColorTexture(r, g, b, a)
    p.borderR:SetColorTexture(r, g, b, a)

    -- Render a genuine annulus, separate from Blizzard's suppressed chrome.
    -- Border textures use a 64px reference diameter and scale with the portrait.
    if p.ringOverlay then
        if (db[pre.."Shape"] or 1) == 1 and a > 0 then
            local diameter = math.max(1, math.min(p.cx, p.cy))
            local ringSize = math.max(1, math.min(12, math.floor(borderSize * 64 / diameter + 0.5)))
            p.ringOverlay:SetTexture(string.format(
                "Interface\\AddOns\\AnimatedBlizzPortrait\\media\\portrait-ring-%02d.tga", ringSize))
            p.ringOverlay:SetSize(p.cx, p.cy)
            p.ringOverlay:SetVertexColor(r, g, b, a)
            if p.ringFrame then p.ringFrame:Show() end
            p.ringOverlay:Show()
        else
            p.ringOverlay:Hide()
            if p.ringFrame then p.ringFrame:Hide() end
        end
    end
end

-------------------------------------------------------------------------------
-- Model loading
--
-- Two separate reasons a unit's model can fail to appear, which need opposite
-- responses:
--
-- 1. Restricted identity (Midnight).  As of patch 12.0.5, Model:SetUnit
--    "requires declassified unit identity", and unit identity is secret "while
--    on instanced maps for any unit that isn't the player, their pet/vehicle, or
--    a raid/party member".  SetUnit then returns nil instead of its usual
--    success value and does nothing.  This is a deliberate Blizzard restriction,
--    so no amount of retrying helps — fall straight back to the 2D portrait.
--
-- 2. Model data still streaming.  SetUnit returns false while the model has not
--    loaded yet, which is most visible right after a zone-in.  Here the model
--    does arrive shortly, so retry and let OnModelLoaded redraw when it lands.
--
-- ClearModel is used only when the frame changes occupant, so a SetUnit that did
-- nothing cannot leave the previous unit — or, after a zone-in resets the frame,
-- the PlayerModel default of the player's own character — on screen.  It must
-- never be a failure response: clearing while a load is in flight aborts that
-- load, so retrying that way can never succeed.
-------------------------------------------------------------------------------
local MODEL_RETRY_DELAYS = { 0.5, 1, 2, 4, 8 }

local function ApplyUnitModel(p, unit, texture)
    local guid = UnitGUID(unit)
    local _isec = type(issecretvalue) == "function" and issecretvalue or nil
    if _isec and _isec(guid) then guid = nil end

    if guid ~= p.modelGUID then
        -- New occupant of this frame: drop the old model so a failed SetUnit
        -- cannot leave the previous unit (or the PlayerModel default) on screen.
        -- Only here — clearing for any other reason risks killing a live load.
        p.modelGUID   = guid
        p.modelLoaded = false
        p.modelRetry  = 0
        p.model:ClearModel()
    end

    -- Re-issued on every Draw, exactly as before this change.
    local ok = p.model:SetUnit(unit)

    -- Since 12.0.5 Blizzard returns nil when the unit has secret identity.  Use
    -- the API's result instead of guessing from the instance type: that keeps
    -- every elite/enemy Blizzard still permits animated, and falls back only for
    -- the particular unit the client actually refused.  Older clients predate
    -- this restriction and historically did not guarantee a useful return.
    if ABP.isModernClient and ok == nil then
        p.modelRetry = 0
        return false
    end

    if ok == false and not p.modelLoaded then
        -- Model data is not available yet.  Queue further attempts in case no
        -- other event triggers a redraw before it becomes available.
        local n = (p.modelRetry or 0) + 1
        p.modelRetry = n
        local delay = MODEL_RETRY_DELAYS[n]
        if delay then
            C_Timer.After(delay, function()
                if ABP.portraits[texture] == p and p.unit == unit then
                    ABP:Queue(texture, "low")
                end
            end)
        end
    elseif ok ~= false then
        p.modelRetry = 0
        -- GetModelFileID is retail-only (7.0.3+) and returns nil while the model
        -- is still streaming, so it can confirm a load but never disprove one.
        if p.model.GetModelFileID and p.model:GetModelFileID() then
            p.modelLoaded = true
        end
    end
    return true
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Restricted-model fallback: retain configurable chrome and 2D positioning.
-- The engine-generated portrait includes its own background pixels; a backdrop
-- underneath cannot remove those pixels. Do not use ADD blending as a false
-- transparency fix: it washes out the character as well as the background.
-------------------------------------------------------------------------------
function ABP:ApplyStaticPortrait(p, unit)
    if not (self.supportsCustomFrameOptions and p.clip and p.model) then return false end
    if not p.staticPortrait then
        p.staticPortrait = p.clip:CreateTexture(nil, "ARTWORK")
        p.staticPortrait.noABP = true -- SetPortraitTexture hook must not re-import this copy.
        p.staticPortrait:Hide()
        p.staticPortrait:SetAllPoints(p.model)
        p.staticMask = p.clip:CreateMaskTexture()
        p.staticMask:SetAllPoints(p.staticPortrait)
        p.staticMask:SetTexture("Interface\\Masks\\CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    local portrait = p.staticPortrait
    -- Mainline can disable the engine's circle so our selected shape controls
    -- clipping. Older clients retain the native portrait call/appearance.
    local ok = pcall(SetPortraitTexture, portrait, unit, self.isModernClient and true or nil)
    if not ok then portrait:Hide(); return false end
    local square = (self.db[UnitPrefix(unit).."Shape"] or 1) == 2
    if not square and not p.staticMasked then
        portrait:AddMaskTexture(p.staticMask); p.staticMasked = true
    elseif square and p.staticMasked then
        portrait:RemoveMaskTexture(p.staticMask); p.staticMasked = false
    end
    self:PositionModel(p, unit)
    self:ApplyBackground(p, unit)
    for _, edge in ipairs({p.borderT, p.borderB, p.borderL, p.borderR}) do edge:SetShown(square) end
    self:ApplyBorderColor(p, unit)
    if p.sqFrame then
        -- Bar borders are independent of the portrait's Circle/Square choice.
        self:ApplyBarFrameLayout(p, unit)
        self:ApplyBarBorderColor(p, unit)
        p.sqFrame:Show()
    end
    portrait:Show()
    return true
end

-------------------------------------------------------------------------------
-- Draw
-------------------------------------------------------------------------------
function ABP:Draw(texture)
    local p      = self.portraits[texture]
    if not p then return end

    -- Keep p.cx/p.cy in sync with the texture's actual current size.
    -- p.clip uses SetAllPoints(texture) so it always tracks the texture, but
    -- dependent calculations (PositionModel inset, sqFrame sizing) still read
    -- p.cx/p.cy — refresh them here so they stay accurate if the texture is
    -- resized after portrait creation.
    local curW, curH = texture:GetWidth(), texture:GetHeight()
    if issecretvalue and (issecretvalue(curW) or issecretvalue(curH)) then return end
    if curW > 0 then p.cx = curW end
    if curH > 0 then p.cy = curH end

    local unit   = p.unit
    local db     = self.db
    local pre    = UnitPrefix(unit)
    local parent = texture:GetParent()

    -- Animated portraits are attempted everywhere, instances included.  Whether
    -- one is possible is decided per unit by ApplyUnitModel — which follows
    -- Blizzard's restricted-identity rule — rather than by instance type, so any
    -- unit whose model the client will supply gets animated.
    local shouldShow = unit
        and UnitIsVisible(unit)
        and parent:IsVisible()
        and p.cx >= MIN_SIZE
        and (not parent.unit or parent.unit == unit)

    local modelUnavailable = false
    if shouldShow and not ApplyUnitModel(p, unit, texture) then
        shouldShow       = false
        modelUnavailable = true
    end

    if not p.blizzRings then ScanBlizzRings(p, texture) end

    local shape  = db[pre.."Shape"] or 1
    local sqMode = self.supportsCustomFrameOptions and (shape == 2)

    -- Lazy-create a custom backdrop to replace the hidden Blizzard chrome.
    if not p.sqFrame and p.blizzRings then
        local grandpa = parent:GetParent()
        if grandpa then
            -- Find the base PortraitOn texture (no suffix like -Vehicle/-InCombat)
            local chromeTex = nil
            for _, r in ipairs(p.blizzRings) do
                local atlas = SafeRegionValue(r, r.GetAtlas) or ""
                if atlas:find("PortraitOn") and not atlas:match("PortraitOn%-") then
                    chromeTex = r
                    break
                end
            end
            -- Fallback: any PortraitOn texture
            if not chromeTex then
                for _, r in ipairs(p.blizzRings) do
                    if (SafeRegionValue(r, r.GetAtlas) or ""):find("PortraitOn") then
                        chromeTex = r; break
                    end
                end
            end
            -- Create sqFrame whenever grandpa exists.
            -- Use chromeTex for the right-edge anchor if available; fall back to grandpa.
            if grandpa then
                p.sqFrame = CreateFrame("Frame", nil, grandpa, "BackdropTemplate")
                p.sqGrandpa = grandpa
                if pre ~= "target" and pre ~= "focus" then
                    -- Portrait on LEFT (player / party)
                    local yOff       = -math.floor(p.cy * 0.32)
                    local rightAnchor = chromeTex or grandpa
                    p.sqSide = "left"
                    p.sqRightAnchor = rightAnchor
                    p.sqFrame:SetHeight(math.floor(p.cy * 0.62))
                    p.sqFrame:SetPoint("TOPLEFT",  p.clip,       "TOPRIGHT", 0,  yOff)
                    p.sqFrame:SetPoint("TOPRIGHT", rightAnchor,  "TOPRIGHT", -4, yOff)
                else
                    -- Portrait on RIGHT (target / focus): anchor off grandpa top
                    local yOff = -math.floor(p.cy * 0.62) - 2
                    p.sqSide = "right"
                    p.sqFrame:SetHeight(math.floor(p.cy * 0.62) + 2)
                    p.sqFrame:SetPoint("TOPLEFT",  grandpa, "TOPLEFT",  math.floor(p.cx * 0.38), yOff)
                    p.sqFrame:SetPoint("TOPRIGHT", p.clip,  "TOPLEFT", 1, yOff)
                end
                -- Dark fill with optional configurable edge border.
                if p.sqFrame.SetBackdrop then
                    p.sqFrame:SetBackdrop({
                        bgFile   = WHITE_TEX,
                        edgeFile = WHITE_TEX,
                        tile = false,
                        edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 },
                    })
                    p.sqFrame:SetBackdropColor(0, 0, 0, 0)
                    p.sqFrame:SetBackdropBorderColor(0, 0, 0, 0)
                end
                p.sqFrame:SetFrameStrata(UNIT_ART_STRATA)
                p.sqFrame:SetFrameLevel(p.clip:GetFrameLevel() + 1)
                p.sqFrame:Hide()
            end
        end
    end

    if p.staticPortrait then p.staticPortrait:Hide() end

    if shouldShow then
        -- The model itself was already set by ApplyUnitModel above.
        p.model:SetAnimation(((self.isClassicClient or db[pre.."Idle"]) and 0 or ANIM))
        p.model:SetPortraitZoom((db[pre.."Zoom"] or 75) / 100)
        self:PositionModel(p, unit)
        self:ApplyBackground(p, unit)
        p.borderT:SetShown(sqMode)
        p.borderB:SetShown(sqMode)
        p.borderL:SetShown(sqMode)
        p.borderR:SetShown(sqMode)

        if p.sqFrame then
            if self.supportsCustomFrameOptions then
                self:ApplyBarFrameLayout(p, unit)
                p.sqFrame:Show()
                self:ApplyBarBorderColor(p, unit)
            else
                p.sqFrame:Hide()
            end
        end
        if unit == "player" then
            self:RefreshPlayerClassPower(p)
        end

        -- ── Blizzard ring textures: always suppressed ─────────────────────
        -- The originals sit on the unit frame, below the model's raised frame level, so
        -- leaving them lit would put the chrome behind the model and let the
        -- model's clip rect cover its inner edge.
        for _, r in ipairs(p.blizzRings or {}) do
            r:SetVertexColor(1, 1, 1, 0)
        end

        -- Portrait border follows the selected shape and appearance settings.
        self:ApplyBorderColor(p, unit)

        texture:Hide()
        p.model:Show()
    else
        -- Unit not visible / blocked: show the original 2D portrait. Paint it
        -- ourselves instead of trusting whatever was already on the texture —
        -- on some clients nothing ever calls SetPortraitTexture for this frame,
        -- leaving it blank instead of showing a static fallback image.
        if unit then
            local ok, exists = pcall(UnitExists, unit)
            if ok and exists then
                pcall(SetPortraitTexture, texture, unit)
            end
        end
        texture:Show()
        p.back:Hide()
        p.backSq:Hide()
        p.borderT:Hide(); p.borderB:Hide()
        p.borderL:Hide(); p.borderR:Hide()
        p.ringOverlay:Hide()
        if p.ringFrame     then p.ringFrame:Hide()     end
        if p.sqFrame       then p.sqFrame:Hide()       end
        if unit == "player" then self:HidePlayerClassPower(p) end
        p.model:Hide()

        -- Keep the configurable layout on visible restricted targets. Invisible
        -- units and Classic retain the original static portrait path.
        if modelUnavailable and self.ApplyStaticPortrait and self:ApplyStaticPortrait(p, unit) then
            texture:Hide()
        end

        -- Changing from a 3D model to a static portrait must not restore Retail's
        -- combined portrait/bar chrome: that artwork overrides the independent
        -- transparent portrait and bar-border settings. Keep the same native
        -- chrome suppression used by the animated portrait. Classic has no custom
        -- frame controls, so retain its existing classification-tinted fallback.
        local showRings = not self.supportsCustomFrameOptions
            and modelUnavailable and unit and not UnitPlayerControlled(unit)
        if showRings then
            local tr, tg, tb, ta = GetClassificationBorderColor(unit)
            local ringR = ta > 0 and tr or 1
            local ringG = ta > 0 and tg or 1
            local ringB = ta > 0 and tb or 1
            for _, r in ipairs(p.blizzRings or {}) do
                r:SetVertexColor(ringR, ringG, ringB, 1)
            end
        else
            for _, r in ipairs(p.blizzRings or {}) do
                r:SetVertexColor(1, 1, 1, self.isClassicClient and 1 or 0)
            end
        end
    end

end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------
function ABP:RefreshAll()
    self:RefreshAllBarColors()
    self:RefreshAllNameStyles()
    self:UpdateBlizzardClassPowerVisibility()
    for texture, p in pairs(self.portraits) do
        p.blizzRings = nil   -- force re-scan so filter changes take effect immediately
        if p.model:GetParent():IsVisible() then
            self:Queue(texture, "high")
        end
    end
    self:RefreshPlayerClassPower()
end

-- A zone-in resets model frames to their default content and streams the new
-- zone's model data in over the following seconds.  Blizzard does not repaint
-- every portrait afterwards, and OnSetPortraitTexture only queues a redraw when
-- the unit's GUID changed — which it has not for a unit you zoned in with.
-- Invalidate the cached model state so the next Draw does a clean clear + set,
-- and let ApplyUnitModel's retry ladder cover anything still streaming.
function ABP:ReloadAllModels()
    for texture, p in pairs(self.portraits) do
        p.modelGUID   = nil
        p.modelLoaded = false
        p.modelRetry  = 0
        self:Queue(texture, "low")
    end
end

-------------------------------------------------------------------------------
-- UI — colour palette (GrindTracker / SimpleGuildRecruiter style)
-------------------------------------------------------------------------------

local Appearance = {
    defaults = {
        background = MODERN_BG, panel = MODERN_PANEL, field = MODERN_FIELD,
        text = MODERN_TEXT, muted = MODERN_MUTED, border = MODERN_BORDER,
        dark = {0.045, 0.060, 0.078, 0.95}, hover = {0.105, 0.145, 0.190, 0.96},
        press = {0.030, 0.040, 0.055, 0.98}, active = {0.090, 0.125, 0.165, 0.96},
    },
    forever = {
        background = {0.105, 0.070, 0.032, 0.97}, panel = {0.175, 0.105, 0.035, 0.94},
        field = {0.105, 0.068, 0.028, 0.96}, text = {0.94, 0.90, 0.80, 1},
        muted = {0.74, 0.69, 0.58, 1}, border = {0.58, 0.40, 0.15, 1},
        dark = {0.105, 0.068, 0.028, 0.96}, hover = {0.29, 0.19, 0.065, 0.96},
        press = {0.065, 0.040, 0.015, 0.98}, active = {0.22, 0.145, 0.045, 0.96},
    },
    colors = setmetatable({}, {__mode = "k"}),
    backdrops = setmetatable({}, {__mode = "k"}),
    palette = {},
}
for key, color in pairs(Appearance.defaults) do
    Appearance.palette[key] = {unpack(color)}
end
local SILVER = Appearance.palette.text
local STEEL = Appearance.palette.border
local DARK = Appearance.palette.dark
local HOVER = Appearance.palette.hover
local PRESS = Appearance.palette.press
local ACTIVE = Appearance.palette.active

-- Track only settings colors. User-selected portrait colors remain independent.
local function ThemeColor(widget, method, palette, alpha)
    local methods = Appearance.colors[widget] or {}
    Appearance.colors[widget] = methods
    methods[method] = {palette = palette, alpha = alpha}
    widget[method](widget, palette[1], palette[2], palette[3], alpha or palette[4] or 1)
end
local CONTROL_BTN_W = 72
local CONTROL_BTN_H = 22

local function ApplyBackdrop(f)
    if not f.SetBackdrop then return end
    Appearance.backdrops[f] = true
    local classic = ABP.db and ABP.db.settingsAppearance == "forever" and f:GetHeight() > 40
    f:SetBackdrop(classic and {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = {left = 8, right = 8, top = 8, bottom = 8},
    } or {
        bgFile   = WHITE_TEX,
        edgeFile = WHITE_TEX,
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    ThemeColor(f, "SetBackdropColor", Appearance.palette.background)
    ThemeColor(f, "SetBackdropBorderColor", STEEL)
end

function ABP:ApplySettingsAppearance()
    local preset = self.db and self.db.settingsAppearance == "forever" and Appearance.forever or Appearance.defaults
    for key, color in pairs(preset) do
        local target = Appearance.palette[key]
        for i = 1, 4 do target[i] = color[i] end
    end
    -- Reapply frame artwork first; restore field overrides and control states below.
    for frame in pairs(Appearance.backdrops) do
        local methods = Appearance.colors[frame]
        local bg = methods and methods.SetBackdropColor
        local border = methods and methods.SetBackdropBorderColor
        ApplyBackdrop(frame)
        if bg then methods.SetBackdropColor = bg end
        if border then methods.SetBackdropBorderColor = border end
    end
    for widget, methods in pairs(Appearance.colors) do
        for method, info in pairs(methods) do
            local color = info.palette
            widget[method](widget, color[1], color[2], color[3], info.alpha or color[4] or 1)
        end
    end
    if self.settingsPanel and self.settingsPanel.RefreshAppearanceControls then
        self.settingsPanel.RefreshAppearanceControls()
    end
end

-- Custom button with steel pixel edges (matches reference addons)
local function MakeBtn(parent, w, h, label)
    local b  = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    ThemeColor(bg, "SetColorTexture", DARK)
    b.bg = bg

    local function Edge(pt, ew, eh)
        local e = b:CreateTexture(nil, "BORDER")
        ThemeColor(e, "SetColorTexture", STEEL)
        e:SetPoint(pt)
        e:SetSize(ew, eh)
    end
    Edge("TOPLEFT",    w, 1)
    Edge("BOTTOMLEFT", w, 1)
    Edge("TOPLEFT",    1, h)
    Edge("TOPRIGHT",   1, h)

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", b, "LEFT", 4, 0)
    fs:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    fs:SetPoint("TOP", b, "TOP", 0, -1)
    fs:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    ThemeColor(fs, "SetTextColor", SILVER)
    fs:SetFont(ABP_UI_FONT, 11, "")
    fs:SetWordWrap(false)
    fs:SetText(label or "")
    if b.SetFontString then b:SetFontString(fs) end
    -- A plain CreateFrame("Button") has no font object, and Button:SetText()
    -- stamps that (nil) font object onto the button's fontstring — which clears
    -- the font set above and renders the label invisibly.  Give the button a real
    -- font object first, then restore our font and colour on the fontstring,
    -- because both calls re-stamp it.
    if b.SetNormalFontObject then b:SetNormalFontObject(GameFontNormalSmall) end
    if b.SetText then b:SetText(label or "") end
    fs:SetFont(ABP_UI_FONT, 11, "")
    ThemeColor(fs, "SetTextColor", SILVER)
    b.label = fs
    b.abpLabelText = label or ""

    b:SetScript("OnEnter",     function() ThemeColor(bg, "SetColorTexture", HOVER) end)
    b:SetScript("OnLeave",     function() ThemeColor(bg, "SetColorTexture", DARK)  end)
    b:SetScript("OnMouseDown", function() ThemeColor(bg, "SetColorTexture", PRESS) end)
    b:SetScript("OnMouseUp",   function() ThemeColor(bg, "SetColorTexture", HOVER) end)
    return b
end

local function SecLabel(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    ThemeColor(fs, "SetTextColor", SILVER)
    fs:SetFont(ABP_UI_FONT, 13, "")
    fs:SetText(text)
    return fs
end

local function HDivider(parent, x, y, w)
    local d = parent:CreateTexture(nil, "ARTWORK")
    ThemeColor(d, "SetColorTexture", STEEL, 0.45)
    d:SetSize(w, 1)
    d:SetPoint("TOPLEFT", x, y)
    return d
end

local function GroupDivider(parent, text, x, y, w)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    ThemeColor(bg, "SetColorTexture", Appearance.palette.panel, 0.55)
    bg:SetSize(w, 18)
    bg:SetPoint("TOPLEFT", x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", bg, "LEFT", 6, 0)
    ThemeColor(fs, "SetTextColor", SILVER)
    fs:SetFont(ABP_UI_FONT, 13, "OUTLINE")
    fs:SetText(text)
    return fs
end

local function SetWidgetsShown(widgets, shown)
    for _, widget in ipairs(widgets) do
        if widget and widget.SetShown then
            widget:SetShown(shown)
        end
    end
end

-------------------------------------------------------------------------------
-- Slider with mousewheel support
-------------------------------------------------------------------------------
local sliderIdx = 0
local function MakeSlider(parent, minV, maxV, defV, width, onChange)
    sliderIdx = sliderIdx + 1
    local s = CreateFrame("Slider", "ABPSl" .. sliderIdx, parent, "OptionsSliderTemplate")
    s:SetWidth(width or 240)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)
    s:SetValue(defV)

    -- Child labels (parentKey based in template)
    if s.Text  then s.Text:SetText(tostring(defV))   end
    if s.Low   then s.Low:SetText(tostring(minV))     end
    if s.High  then s.High:SetText(tostring(maxV))    end
    -- Fallback via globals
    local gText = _G["ABPSl" .. sliderIdx .. "Text"]
    local gLow  = _G["ABPSl" .. sliderIdx .. "Low"]
    local gHigh = _G["ABPSl" .. sliderIdx .. "High"]
    if gText  then gText:SetText(tostring(defV))  end
    if gLow   then gLow:SetText(tostring(minV))   end
    if gHigh  then gHigh:SetText(tostring(maxV))  end
    if gLow   then ThemeColor(gLow, "SetTextColor", Appearance.palette.muted, 1) end
    if gHigh  then ThemeColor(gHigh, "SetTextColor", Appearance.palette.muted, 1) end
    if gText  then ThemeColor(gText, "SetTextColor", SILVER, 1) end
    if s.Low  then ThemeColor(s.Low, "SetTextColor", Appearance.palette.muted, 1) end
    if s.High then ThemeColor(s.High, "SetTextColor", Appearance.palette.muted, 1) end
    if s.Text then ThemeColor(s.Text, "SetTextColor", SILVER, 1) end

    local left = _G["ABPSl" .. sliderIdx .. "Left"]
    local middle = _G["ABPSl" .. sliderIdx .. "Middle"]
    local right = _G["ABPSl" .. sliderIdx .. "Right"]
    if left then left:SetAlpha(0) end
    if middle then middle:SetAlpha(0) end
    if right then right:SetAlpha(0) end

    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(3)
    ThemeColor(track, "SetColorTexture", STEEL, 0.45)

    local thumb = _G["ABPSl" .. sliderIdx .. "Thumb"]
    if thumb then
        thumb:SetTexture(WHITE_TEX)
        thumb:SetSize(8, 14)
        ThemeColor(thumb, "SetVertexColor", SILVER, 1)
    end

    local function UpdateText(val)
        if s.Text then s.Text:SetText(tostring(val)) end
        if gText  then gText:SetText(tostring(val))  end
    end

    s:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        UpdateText(val)
        onChange(val)
    end)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta)
    end)

    -- Method so callers can sync value without firing onChange
    function s:Sync(val)
        s:SetScript("OnValueChanged", nil)
        s:SetValue(val)
        UpdateText(val)
        s:SetScript("OnValueChanged", function(self2, v)
            v = math.floor(v + 0.5)
            UpdateText(v)
            onChange(v)
        end)
    end

    return s
end

-------------------------------------------------------------------------------
-- Option-row: radio-style buttons  (MakeBtn, active state highlighted)
-------------------------------------------------------------------------------
local function MakeOptionRow(parent, names, yTop, getValue, setValue, extraOnClick, opts)
    opts = opts or {}
    local buttons = {}
    local gap = opts.gap or 4
    local startX = opts.startX or 10
    local btnH = opts.buttonH or CONTROL_BTN_H
    local btnW = opts.buttonW or CONTROL_BTN_W
    -- Shrink buttons when they would overflow the available width
    if opts.maxWidth and #names > 0 then
        local fitW = math.floor((opts.maxWidth - (#names - 1) * gap) / #names)
        if fitW < btnW then btnW = math.max(44, fitW) end
    end

    local function Refresh()
        local cur = getValue()
        for i, btn in ipairs(buttons) do
            if i == cur then
                ThemeColor(btn.bg, "SetColorTexture", ACTIVE)
                ThemeColor(btn.label, "SetTextColor", SILVER, 1)
            else
                ThemeColor(btn.bg, "SetColorTexture", DARK)
                ThemeColor(btn.label, "SetTextColor", Appearance.palette.muted, 1)
            end
        end
    end

    for i, name in ipairs(names) do
        local btn = MakeBtn(parent, btnW, btnH, name)
        btn:SetPoint("TOPLEFT", startX + (i - 1) * (btnW + gap), yTop)
        -- Override MakeBtn's generic hover scripts so active tab stays lit
        btn:SetScript("OnEnter", function()
            if getValue() ~= i then ThemeColor(btn.bg, "SetColorTexture", HOVER) end
        end)
        btn:SetScript("OnLeave", function()
            if getValue() == i then
                ThemeColor(btn.bg, "SetColorTexture", ACTIVE)
            else
                ThemeColor(btn.bg, "SetColorTexture", DARK)
            end
        end)
        btn:SetScript("OnMouseDown", function()
            if getValue() ~= i then ThemeColor(btn.bg, "SetColorTexture", PRESS) end
        end)
        btn:SetScript("OnMouseUp", function()
            if getValue() ~= i then ThemeColor(btn.bg, "SetColorTexture", HOVER) end
        end)
        btn:SetScript("OnClick", function()
            setValue(i)
            Refresh()
            if extraOnClick then extraOnClick(i) end
            ABP:RefreshAll()
        end)
        buttons[i] = btn
    end

    Refresh()
    return buttons, Refresh, {
        startX = startX,
        gap = gap,
        buttonW = btnW,
        buttonH = btnH,
        right = startX + (#names * btnW) + ((#names - 1) * gap),
    }
end

-------------------------------------------------------------------------------
-- Toggle button (MakeBtn, colour-coded ON / OFF)
-------------------------------------------------------------------------------
local function MakeToggle(parent, yTop, getValue, setValue, xOff)
    local btn = MakeBtn(parent, CONTROL_BTN_W, CONTROL_BTN_H, "")

    local function Refresh()
        if getValue() then
            btn.label:SetText("ON")
            ThemeColor(btn.label, "SetTextColor", SILVER, 1)
            ThemeColor(btn.bg, "SetColorTexture", ACTIVE)
        else
            btn.label:SetText("OFF")
            ThemeColor(btn.label, "SetTextColor", Appearance.palette.muted, 1)
            ThemeColor(btn.bg, "SetColorTexture", DARK)
        end
    end

    btn:SetPoint("TOPLEFT", xOff or 10, yTop)
    -- Suppress generic hover so colour stays correct
    btn:SetScript("OnEnter",     function() end)
    btn:SetScript("OnLeave",     function() end)
    btn:SetScript("OnMouseDown", function() end)
    btn:SetScript("OnMouseUp",   function() end)
    btn:SetScript("OnClick", function()
        setValue(not getValue())
        Refresh()
        ABP:RefreshAll()
    end)

    Refresh()
    return btn, Refresh
end

local function MakeToggleChipRow(parent, items, yTop, opts)
    opts = opts or {}
    local buttons = {}
    local startX = opts.startX or 10
    local gap = opts.gap or 6
    local btnW = opts.buttonW or CONTROL_BTN_W
    local btnH = opts.buttonH or CONTROL_BTN_H

    local function Refresh()
        for i, item in ipairs(items) do
            local btn = buttons[i]
            local on = item.getValue()
            btn.label:SetText(item.label)
            if on then
                ThemeColor(btn.bg, "SetColorTexture", ACTIVE)
                ThemeColor(btn.label, "SetTextColor", SILVER, 1)
            else
                ThemeColor(btn.bg, "SetColorTexture", DARK)
                ThemeColor(btn.label, "SetTextColor", Appearance.palette.muted, 1)
            end
        end
    end

    for i, item in ipairs(items) do
        local btn = MakeBtn(parent, btnW, btnH, item.label)
        btn:SetPoint("TOPLEFT", startX + (i - 1) * (btnW + gap), yTop)
        btn:SetScript("OnEnter", function()
            if not item.getValue() then ThemeColor(btn.bg, "SetColorTexture", HOVER) end
        end)
        btn:SetScript("OnLeave", function()
            if item.getValue() then
                ThemeColor(btn.bg, "SetColorTexture", ACTIVE)
            else
                ThemeColor(btn.bg, "SetColorTexture", DARK)
            end
        end)
        btn:SetScript("OnMouseDown", function()
            if not item.getValue() then ThemeColor(btn.bg, "SetColorTexture", PRESS) end
        end)
        btn:SetScript("OnMouseUp", function()
            if not item.getValue() then ThemeColor(btn.bg, "SetColorTexture", HOVER) end
        end)
        btn:SetScript("OnClick", function()
            item.setValue(not item.getValue())
            Refresh()
            if item.onClick then item.onClick() end
            ABP:RefreshAll()
        end)
        buttons[i] = btn
    end

    Refresh()
    return buttons, Refresh, {
        right = startX + (#items * btnW) + ((#items - 1) * gap),
    }
end

-------------------------------------------------------------------------------
-- X / Y slider pair  (sliderW passed by caller to account for preview column)
-- ASCII direction hints: < > ^ v  (no Unicode — avoids [] rendering in-game)
-------------------------------------------------------------------------------
local function MakeXYSliders(contentFrame, xKey, yKey, sliderW)
    local db = ABP.db
    local sw = sliderW or 330

    SecLabel(contentFrame, "X Offset     < left   |   right >", 10, -40)
    local xSlider = MakeSlider(contentFrame, -30, 30, db[xKey] or 0, sw, function(val)
        ABP.db[xKey] = val
        ABP:RefreshAll()
    end)
    xSlider:SetPoint("TOPLEFT", 10, -72)   -- extra gap so value text clears the label

    SecLabel(contentFrame, "Y Offset     v down   |   up  ^", 10, -116)
    local ySlider = MakeSlider(contentFrame, -30, 30, db[yKey] or 0, sw, function(val)
        ABP.db[yKey] = val
        ABP:RefreshAll()
    end)
    ySlider:SetPoint("TOPLEFT", 10, -148)  -- same extra gap

    contentFrame.SyncSliders = function()
        xSlider:Sync(ABP.db[xKey] or 0)
        ySlider:Sync(ABP.db[yKey] or 0)
    end
end

-------------------------------------------------------------------------------
-- Color picker wrapper (TWW+)
-------------------------------------------------------------------------------
local function OpenColorPicker(r, g, b, a, onUpdate)
    if not ColorPickerFrame then
        return
    end

    local prev = { r = r, g = g, b = b, a = a }
    local usesDirectAlpha = ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker
    local function onChange()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local alphaValue
        if ColorPickerFrame.GetColorAlpha then
            alphaValue = ColorPickerFrame:GetColorAlpha()
        elseif OpacitySliderFrame and OpacitySliderFrame.GetValue then
            alphaValue = OpacitySliderFrame:GetValue()
        else
            alphaValue = 0
        end
        -- Mainline's ColorSelect returns alpha directly. Legacy opacity sliders
        -- use the inverse convention; applying that inversion on Retail made
        -- transparent selections become opaque (and vice versa).
        local na = usesDirectAlpha and alphaValue or (1 - alphaValue)
        onUpdate(nr, ng, nb, na)
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r           = r,
            g           = g,
            b           = b,
            hasOpacity  = true,
            opacity     = usesDirectAlpha and a or (1 - a),
            swatchFunc  = onChange,
            opacityFunc = onChange,
            cancelFunc  = function() onUpdate(prev.r, prev.g, prev.b, prev.a) end,
        })
    else
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = 1 - a
        ColorPickerFrame.previousValues = { r, g, b, 1 - a }
        ColorPickerFrame.func = onChange
        ColorPickerFrame.opacityFunc = onChange
        ColorPickerFrame.cancelFunc = function(previousValues)
            if previousValues then
                onUpdate(previousValues[1], previousValues[2], previousValues[3], 1 - (previousValues[4] or 0))
            else
                onUpdate(prev.r, prev.g, prev.b, prev.a)
            end
        end
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

local function MakeColorSwatch(parent, x, y, getColor, setColor, refreshFunc, caption)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(24, 22)
    btn:SetPoint("TOPLEFT", x, y)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetTexture(WHITE_TEX)
    ThemeColor(border, "SetVertexColor", STEEL, 1)

    if caption then
        btn.caption = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.caption:SetPoint("CENTER")
        btn.caption:SetFont(ABP_UI_FONT, 10, "OUTLINE")
        btn.caption:SetTextColor(1, 1, 1, 1)
        btn.caption:SetText(caption)
    end

    function btn:Refresh()
        local r, g, b, a = getColor()
        tex:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
    end

    btn:SetScript("OnClick", function()
        local r, g, b, a = getColor()
        OpenColorPicker(r or 1, g or 1, b or 1, a or 1, function(nr, ng, nb, na)
            setColor(nr, ng, nb, na)
            btn:Refresh()
            if refreshFunc then refreshFunc() else ABP:RefreshAllBarColors() end
        end)
    end)

    btn:Refresh()
    return btn
end

local function StyleScrollFrame(scrollFrame)
    local scrollBar = scrollFrame and (scrollFrame.ScrollBar or _G[(scrollFrame:GetName() or "") .. "ScrollBar"])
    if not scrollBar then return end

    local thumb = scrollBar.ThumbTexture or _G[(scrollBar:GetName() or "") .. "ThumbTexture"]
    if thumb then
        thumb:SetTexture(WHITE_TEX)
        ThemeColor(thumb, "SetVertexColor", SILVER, 0.72)
    end

    local upButton = scrollBar.ScrollUpButton or _G[(scrollBar:GetName() or "") .. "ScrollUpButton"]
    local downButton = scrollBar.ScrollDownButton or _G[(scrollBar:GetName() or "") .. "ScrollDownButton"]
    for _, button in ipairs({ upButton, downButton }) do
        if button then
            button:SetAlpha(0)
            button:EnableMouse(false)
        end
    end
end

-------------------------------------------------------------------------------
-- Settings panel  (540 × 310 — GrindTracker / SGR style)
-------------------------------------------------------------------------------
function ABP:BuildSettingsPanel()
    self:ApplySettingsAppearance()
    -- Re-check right before building the panel: some hybrid/fan clients (e.g.
    -- "WoW Forever") don't have WOW_PROJECT_MAINLINE defined yet even by
    -- PLAYER_LOGIN, so this is the latest and most reliable point to check it.
    do
        local isMainlineProject = WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
        self.isModernClient = CLIENT_BUILD >= 120000 or isMainlineProject
        self.isClassicClient = CLIENT_BUILD < 40000 and not isMainlineProject
        self.supportsCustomFrameOptions = not self.isClassicClient
    end
    local db = self.db
    local PW = 620
    local PH = 700

    local TITLE_Y   = -14
    local DIV1_Y    = -48
    local TAB_Y     = -58
    local TAB_H     = 22
    local TAB_W     = 116   -- 5×116 + 4×4 = 596, centred in 620
    local TAB_GAP   = 4
    local DIV2_Y    = -84
    local CONTENT_Y = -88

    local PREV_W  = 150   -- single preview width
    local PREV_H  = 128   -- snug around 96px model

    local panel = CreateFrame("Frame", "ABPSettingsPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PW, PH)
    panel:SetPoint("CENTER")
    panel:Hide()
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(100)
    ApplyBackdrop(panel)

    local headerBg = panel:CreateTexture(nil, "BACKGROUND")
    headerBg:SetPoint("TOPLEFT", 1, -1)
    headerBg:SetPoint("TOPRIGHT", -1, -1)
    headerBg:SetHeight(48)
    ThemeColor(headerBg, "SetColorTexture", Appearance.palette.panel)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, TITLE_Y)
    ThemeColor(title, "SetTextColor", SILVER)
    title:SetFont(ABP_UI_FONT, 18, "")
    title:SetText("Animated Blizzard Portraits")
    HDivider(panel, 10, DIV1_Y, PW - 20)

    local closeBtn = MakeBtn(panel, 22, 22, "X")
    closeBtn:SetPoint("TOPRIGHT", -10, -11)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)

    --------------------------------------------------------------------------
    -- Tab strip  (Player / Pet / Target / Focus / Party / Profiles)
    --------------------------------------------------------------------------
    local TAB_NAMES = { "Player", "Pet", "Target", "Focus", "Party", "Profiles" }
    local tabButtonW = math.floor((PW - 20 - ((#TAB_NAMES - 1) * TAB_GAP)) / #TAB_NAMES)
    local totalTabW = #TAB_NAMES * tabButtonW + (#TAB_NAMES - 1) * TAB_GAP
    local tabStartX = math.floor((PW - totalTabW) / 2)

    local tabs      = {}
    local tabFrames = {}
    local syncFuncs = {}

    local function SelectTab(idx)
        for i = 1, #tabs do
            local active = (i == idx)
            ThemeColor(tabs[i].bg, "SetColorTexture", active and ACTIVE or DARK)
            if active then
                ThemeColor(tabs[i].label, "SetTextColor", SILVER, 1)
            else
                ThemeColor(tabs[i].label, "SetTextColor", Appearance.palette.muted, 1)
            end
            tabFrames[i]:SetShown(active)
        end
        if tabFrames[idx] and tabFrames[idx].scrollFrame then
            tabFrames[idx].scrollFrame:SetVerticalScroll(0)
        end
        if syncFuncs[idx] then syncFuncs[idx]() end
    end

    for i, name in ipairs(TAB_NAMES) do
        local btn = MakeBtn(panel, tabButtonW, TAB_H, name)
        btn:SetPoint("TOPLEFT", tabStartX + (i-1)*(tabButtonW+TAB_GAP), TAB_Y)
        btn:SetScript("OnEnter", function()
            if not tabFrames[i]:IsShown() then ThemeColor(btn.bg, "SetColorTexture", HOVER) end
        end)
        btn:SetScript("OnLeave", function()
            ThemeColor(btn.bg, "SetColorTexture", tabFrames[i]:IsShown() and ACTIVE or DARK)
        end)
        btn:SetScript("OnMouseDown", function()
            if not tabFrames[i]:IsShown() then ThemeColor(btn.bg, "SetColorTexture", PRESS) end
        end)
        btn:SetScript("OnMouseUp", function()
            if not tabFrames[i]:IsShown() then ThemeColor(btn.bg, "SetColorTexture", HOVER) end
        end)
        btn:SetScript("OnClick", function() SelectTab(i) end)
        tabs[i] = btn

        local host = CreateFrame("Frame", nil, panel)
        host:SetPoint("TOPLEFT",     10, CONTENT_Y)
        host:SetPoint("BOTTOMRIGHT", -10, 8)
        host:SetClipsChildren(true)
        host:Hide()

        if i <= 5 then
            local scrollFrame = CreateFrame("ScrollFrame", "ABPTabScrollFrame"..i, host, "UIPanelScrollFrameTemplate")
            scrollFrame:SetPoint("TOPLEFT", 4, -4)
            scrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)
            StyleScrollFrame(scrollFrame)

            local scrollChild = CreateFrame("Frame", nil, scrollFrame)
            scrollChild:SetSize(PW - 56, 2000)
            scrollFrame:SetScrollChild(scrollChild)

            scrollFrame:EnableMouseWheel(true)
            scrollFrame:SetScript("OnMouseWheel", function(self, delta)
                local cur = self:GetVerticalScroll()
                local max = self:GetVerticalScrollRange()
                self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 28)))
            end)

            host.scrollFrame = scrollFrame
            host.content = scrollChild
        else
            host.content = host
        end

        tabFrames[i] = host
    end
    HDivider(panel, 10, DIV2_Y, PW - 20)

    --------------------------------------------------------------------------
    -- Preview box helper  (reads per-unit db keys for background/zoom/idle)
    --------------------------------------------------------------------------
    local function MakePrevBox(parent, units, boxW, boxH, mSize, yTop, pre, xKey, yKey)
        local isMulti = type(units) == "table"
        local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        box:SetSize(boxW, boxH)
        box:SetPoint("TOPRIGHT", -2, yTop or -4)
        ApplyBackdrop(box)

        local lbl = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOP", 0, -7)
        ThemeColor(lbl, "SetTextColor", Appearance.palette.muted, 1)
        lbl:SetFont(ABP_UI_FONT, 11, "")
        lbl:SetText("Preview")

        local entries = {}
        if isMulti then
            local count = #units
            local mW = mSize or math.floor((boxW - (count+1)*8) / count)
            for i, unit in ipairs(units) do
                local xOff = 8 + (i-1)*(mW+8)
                local back = box:CreateTexture(nil, "BACKGROUND")
                back:SetSize(mW, mW); back:SetPoint("TOPLEFT", xOff, -22); back:Hide()
                local mask = box:CreateMaskTexture()
                mask:SetAllPoints(back)
                mask:SetTexture("Interface\\Masks\\CircleMask","CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
                back:AddMaskTexture(mask)
                local backSq = box:CreateTexture(nil, "BACKGROUND")
                backSq:SetSize(mW, mW); backSq:SetPoint("TOPLEFT", xOff, -22); backSq:Hide()
                local m = CreateFrame("PlayerModel", nil, box)
                m:SetSize(mW, mW); m:SetPoint("TOPLEFT", xOff, -22)
                entries[i] = { model=m, back=back, backSq=backSq, unit=unit, pt="TOPLEFT", baseX=xOff, baseY=-22 }
            end
        else
            local mW = mSize or math.min(boxW-20, boxH-44)
            local back = box:CreateTexture(nil, "BACKGROUND")
            back:SetSize(mW, mW); back:SetPoint("TOP", 0, -24); back:Hide()
            local mask = box:CreateMaskTexture()
            mask:SetAllPoints(back)
            mask:SetTexture("Interface\\Masks\\CircleMask","CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
            back:AddMaskTexture(mask)
            local backSq = box:CreateTexture(nil, "BACKGROUND")
            backSq:SetSize(mW, mW); backSq:SetPoint("TOP", 0, -24); backSq:Hide()
            local m = CreateFrame("PlayerModel", nil, box)
            m:SetSize(mW, mW); m:SetPoint("TOP", 0, -24)
            entries[1] = { model=m, back=back, backSq=backSq, unit=units, pt="TOP", baseX=0, baseY=-24 }
        end

        function box:Refresh()
            local xSh   = xKey and (ABP.db[xKey] or 0) or 0
            local ySh   = yKey and (ABP.db[yKey] or 0) or 0
            local bg    = ABP.supportsCustomFrameOptions and (ABP.db[pre.."Bg"] or 1) or 1
            local shape = ABP.supportsCustomFrameOptions and (ABP.db[pre.."Shape"] or 1) or 1
            local zm    = ABP.db[pre.."Zoom"]  or 75
            local idl   = ABP.isClassicClient or (ABP.db[pre.."Idle"] or false)

            local function ShowBgEntry(e, r, g, b, a)
                if shape == 2 then
                    e.back:Hide()
                    e.backSq:SetColorTexture(r, g, b, a or 1); e.backSq:Show()
                else
                    e.backSq:Hide()
                    e.back:SetColorTexture(r, g, b, a or 1); e.back:Show()
                end
            end

            for _, e in ipairs(entries) do
                local u = e.unit
                e.model:SetUnit(UnitExists(u) and u or "player")
                e.model:SetPortraitZoom(zm / 100)
                e.model:SetAnimation(idl and 0 or ANIM)
                e.model:ClearAllPoints()
                e.back:ClearAllPoints()
                e.backSq:ClearAllPoints()
                e.model:SetPoint(e.pt,   e.baseX+xSh, e.baseY+ySh)
                e.back:SetPoint(e.pt,    e.baseX+xSh, e.baseY+ySh)
                e.backSq:SetPoint(e.pt,  e.baseX+xSh, e.baseY+ySh)
                if bg == 1 then
                    e.back:Hide(); e.backSq:Hide()
                elseif bg == 2 then
                    ShowBgEntry(e, 0, 0, 0, 1)
                elseif bg == 3 then
                    local cf = select(2, UnitClass(UnitExists(u) and u or "player"))
                    local c  = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
                    ShowBgEntry(e, c and c.r*.45 or 0, c and c.g*.45 or 0, c and c.b*.45 or 0, 1)
                elseif bg == 4 then
                    ShowBgEntry(e,
                        ABP.db[pre.."BgR"] or 0.1,
                        ABP.db[pre.."BgG"] or 0.1,
                        ABP.db[pre.."BgB"] or 0.1,
                        ABP.db[pre.."BgA"] or 1.0)
                end
            end
        end
        box:SetScript("OnShow", function() box:Refresh() end)
        return box
    end

    --------------------------------------------------------------------------
    -- Per-tab definitions
    --------------------------------------------------------------------------
    local tabDefs = {
        { pre="player", label="Player Portrait", unit="player",
          xKey="playerX", yKey="playerY", sizeKey="playerInset" },
        { pre="pet",    label="Pet Portrait",    unit="pet",
          xKey="petX",    yKey="petY",    sizeKey="petInset"    },
        { pre="target", label="Target Portrait", unit="target",
          xKey="targetX", yKey="targetY", sizeKey="targetInset" },
        { pre="focus",  label="Focus Portrait",  unit="focus",
          xKey="focusX",  yKey="focusY",  sizeKey="focusInset"  },
        { pre="party",  label="Party Portrait",  unit={"party1","party2"},
          xKey="partyX",  yKey="partyY",  sizeKey="partyInset"  },
    }

    for i, t in ipairs(tabDefs) do
        local f       = tabFrames[i].content
        local pre     = t.pre
        local isParty = type(t.unit) == "table"
        local prevW   = isParty and 220 or PREV_W
        local slW     = PW - 20 - prevW - 12 - 10   -- slider / button column width
        local showClassicFrameOptions = self.supportsCustomFrameOptions
        local playerClassTag = (pre == "player") and select(2, UnitClass("player")) or nil
        local playerClassDef = playerClassTag and CLASS_RESOURCE_DEFS[playerClassTag] or nil
        local showClassResourceSettings = pre == "player" and not self.isClassicClient and playerClassDef ~= nil
        local isDeathKnightSettings = showClassResourceSettings and playerClassTag == "DEATHKNIGHT"
        local isRogueSettings = showClassResourceSettings and playerClassTag == "ROGUE"
        local compactClassicOptions = not showClassicFrameOptions
        local function UIY(classicY, modernY)
            return compactClassicOptions and classicY or modernY
        end

        -- Preview (on host so it stays fixed while scrolling)
        local pBox = MakePrevBox(tabFrames[i], t.unit, prevW, PREV_H,
                                 isParty and nil or 96, -4, pre, t.xKey, t.yKey)

        -- Section header
        SecLabel(f, t.label, 10, -8)
        HDivider(f, 10, -22, slW)

        ---------- PORTRAIT group --------------------------------------------
        if showClassicFrameOptions then
            GroupDivider(f, "Portrait", 10, -35, slW)
        end

        local shapeLabel = SecLabel(f, "Background Shape", 10, -61)
        local shapeButtons, refreshShape = MakeOptionRow(f, { "Circle", "Square" }, -77,
            function()  return db[pre.."Shape"] or 1  end,
            function(v) db[pre.."Shape"] = v           end,
            function() pBox:Refresh(); ABP:RefreshAll() end,
            { maxWidth = slW - 12 })
        SetWidgetsShown({ shapeLabel, unpack(shapeButtons) }, showClassicFrameOptions)

        ---------- Background Color ------------------------------------------
        local bgLabel = SecLabel(f, "Background Color", 10, -109)

        local sw = CreateFrame("Button", nil, f)
        sw:SetSize(22, 22)
        sw:SetPoint("TOPLEFT", 10 + #BG_NAMES*76, -125)
        local swTex = sw:CreateTexture(nil, "ARTWORK")
        swTex:SetPoint("TOPLEFT",2,-2); swTex:SetPoint("BOTTOMRIGHT",-2,2)
        swTex:SetColorTexture(db[pre.."BgR"] or 0.1, db[pre.."BgG"] or 0.1, db[pre.."BgB"] or 0.1, 1)
        local swBdr = sw:CreateTexture(nil, "BACKGROUND")
        swBdr:SetAllPoints(); swBdr:SetTexture(WHITE_TEX); ThemeColor(swBdr, "SetVertexColor", STEEL, 1)
        sw:SetScript("OnClick", function()
            OpenColorPicker(db[pre.."BgR"],db[pre.."BgG"],db[pre.."BgB"],db[pre.."BgA"],
                function(r,g,b,a)
                    db[pre.."BgR"],db[pre.."BgG"],db[pre.."BgB"],db[pre.."BgA"] = r,g,b,a
                    swTex:SetColorTexture(r,g,b,1)
                    pBox:Refresh(); ABP:RefreshAll()
                end)
        end)

        local bgButtons, refreshBg, bgRow = MakeOptionRow(f, BG_NAMES, -125,
            function()  return db[pre.."Bg"] or 1  end,
            function(v) db[pre.."Bg"] = v           end,
            function(v) sw:SetShown(v==4); pBox:Refresh() end,
            { maxWidth = slW - 34 })
        sw:ClearAllPoints()
        sw:SetPoint("TOPLEFT", bgRow.right + 6, -125)
        sw:SetShown(showClassicFrameOptions and (db[pre.."Bg"] or 1) == 4)
        SetWidgetsShown({ bgLabel, sw, unpack(bgButtons) }, showClassicFrameOptions)

        ---------- Border Color ----------------------------------------------
        local borderLabel = SecLabel(f, "Border Color", 10, -157)
        local bsw = CreateFrame("Button", nil, f)
        bsw:SetSize(22, 22)
        bsw:SetPoint("TOPLEFT", 10 + #BORDER_NAMES*76, -173)
        local bswTex = bsw:CreateTexture(nil, "ARTWORK")
        bswTex:SetPoint("TOPLEFT",2,-2); bswTex:SetPoint("BOTTOMRIGHT",-2,2)
        bswTex:SetColorTexture(db[pre.."BorderR"] or 0.82, db[pre.."BorderG"] or 0.85, db[pre.."BorderB"] or 0.90, 1)
        local bswBdr = bsw:CreateTexture(nil, "BACKGROUND")
        bswBdr:SetAllPoints(); bswBdr:SetTexture(WHITE_TEX); ThemeColor(bswBdr, "SetVertexColor", STEEL, 1)
        bsw:SetScript("OnClick", function()
            OpenColorPicker(db[pre.."BorderR"] or 0.85, db[pre.."BorderG"] or 0.65, db[pre.."BorderB"] or 0.08, 1,
                function(r,g,b,a)
                    db[pre.."BorderR"], db[pre.."BorderG"], db[pre.."BorderB"] = r, g, b
                    bswTex:SetColorTexture(r, g, b, 1)
                    ABP:RefreshAll()
                end)
        end)
        local borderButtons, refreshBorderC, borderRow = MakeOptionRow(f, BORDER_NAMES, -173,
            function()  return db[pre.."BorderC"] or 1  end,
            function(v) db[pre.."BorderC"] = v           end,
            function(v) bsw:SetShown(v==5); ABP:RefreshAll() end,
            { maxWidth = slW - 34 })
        bsw:ClearAllPoints()
        bsw:SetPoint("TOPLEFT", borderRow.right + 6, -173)
        bsw:SetShown(showClassicFrameOptions and (db[pre.."BorderC"] or 1) == 5)
        SetWidgetsShown({ borderLabel, bsw, unpack(borderButtons) }, showClassicFrameOptions)

        local portraitBorderSizeLabel = SecLabel(f, "Portrait Border Size", 10, -207)
        local portraitBorderSizeSl = MakeSlider(f, 0, 12, db[pre.."BorderSize"] or 2, slW, function(val)
            db[pre.."BorderSize"] = val
            ABP:RefreshAll()
        end)
        portraitBorderSizeSl:SetPoint("TOPLEFT", 10, -225)
        SetWidgetsShown({ portraitBorderSizeLabel, portraitBorderSizeSl }, showClassicFrameOptions)

        ---------- BARS group ------------------------------------------------
        GroupDivider(f, "Bars", 10, UIY(-35, -273), slW)

        ---------- Bar Border Color ------------------------------------------
        local barBorderLabel = SecLabel(f, "HP / Resource Border Color", 10, -299)
        local bbsw = CreateFrame("Button", nil, f)
        bbsw:SetSize(22, 22)
        bbsw:SetPoint("TOPLEFT", 10 + #BAR_BORDER_NAMES*76, -315)
        local bbswTex = bbsw:CreateTexture(nil, "ARTWORK")
        bbswTex:SetPoint("TOPLEFT",2,-2); bbswTex:SetPoint("BOTTOMRIGHT",-2,2)
        bbswTex:SetColorTexture(db[pre.."BarBR"] or 0.82, db[pre.."BarBG"] or 0.85, db[pre.."BarBB"] or 0.90, 1)
        local bbswBdr = bbsw:CreateTexture(nil, "BACKGROUND")
        bbswBdr:SetAllPoints(); bbswBdr:SetTexture(WHITE_TEX); ThemeColor(bbswBdr, "SetVertexColor", STEEL, 1)
        bbsw:SetScript("OnClick", function()
            OpenColorPicker(db[pre.."BarBR"] or 0.82, db[pre.."BarBG"] or 0.85, db[pre.."BarBB"] or 0.90, 1,
                function(r,g,b,a)
                    db[pre.."BarBR"], db[pre.."BarBG"], db[pre.."BarBB"] = r, g, b
                    bbswTex:SetColorTexture(r, g, b, 1)
                    ABP:RefreshAll()
                end)
        end)
        local barBorderButtons, refreshBarBC, barBorderRow = MakeOptionRow(f, BAR_BORDER_NAMES, -315,
            function()  return db[pre.."BarBC"] or 1  end,
            function(v) db[pre.."BarBC"] = v           end,
            function(v) bbsw:SetShown(v==4); ABP:RefreshAll() end,
            { maxWidth = slW - 34 })
        bbsw:ClearAllPoints()
        bbsw:SetPoint("TOPLEFT", barBorderRow.right + 6, -315)
        bbsw:SetShown(showClassicFrameOptions and (db[pre.."BarBC"] or 1) == 4)
        SetWidgetsShown({ barBorderLabel, bbsw, unpack(barBorderButtons) }, showClassicFrameOptions)

        local barBorderSizeLabel = SecLabel(f, "HP / Resource Border Size", 10, -347)
        local barBorderSizeSl = MakeSlider(f, 0, 8, db[pre.."BarBorderSize"] or 1, slW, function(val)
            db[pre.."BarBorderSize"] = val
            ABP:RefreshAll()
        end)
        barBorderSizeSl:SetPoint("TOPLEFT", 10, -365)
        SetWidgetsShown({ barBorderSizeLabel, barBorderSizeSl }, showClassicFrameOptions)

        local barLengthLabel = SecLabel(f, "HP / Resource Bar Length", 10, -411)
        local barLengthSl = MakeSlider(f, -80, 120, db[pre.."BarLength"] or 0, slW, function(val)
            db[pre.."BarLength"] = val
            ABP:RefreshAll()
        end)
        barLengthSl:SetPoint("TOPLEFT", 10, -429)
        SetWidgetsShown({ barLengthLabel, barLengthSl }, showClassicFrameOptions)

        local barHeightLabel = SecLabel(f, "HP / Resource Bar Height", 10, -475)
        local barHeightSl = MakeSlider(f, -24, 60, db[pre.."BarHeight"] or 0, slW, function(val)
            db[pre.."BarHeight"] = val
            ABP:RefreshAll()
        end)
        barHeightSl:SetPoint("TOPLEFT", 10, -493)
        SetWidgetsShown({ barHeightLabel, barHeightSl }, showClassicFrameOptions)

        ---------- Health / Resource Bar Colors ------------------------------
        local healthStartSw, healthEndSw, resourceStartSw, resourceEndSw
        local healthStartLbl, healthEndLbl, resourceStartLbl, resourceEndLbl
        local refreshHealthClassColor = function() end
        local refreshResourceClassColor = function() end
        local refreshBarEffects = function() end
        local refreshBarTexture = function() end

        local function SetColorTriplet(baseKey, r, g, b)
            db[pre..baseKey.."R"], db[pre..baseKey.."G"], db[pre..baseKey.."B"] = r, g, b
        end

        local function UpdateBarSwatchVisibility()
            local healthMode   = db[pre.."HealthColorMode"]   or 1
            local resourceMode = db[pre.."ResourceColorMode"] or 1

            -- S/E swatches only shown for Solid (2) or Gradient (3); hidden for Default (1) and Class Color (4)
            healthStartSw:SetShown(healthMode == 2 or healthMode == 3)
            healthEndSw:SetShown(healthMode == 3)
            healthStartLbl:SetShown(healthMode == 2 or healthMode == 3)
            healthEndLbl:SetShown(healthMode == 3)

            resourceStartSw:SetShown(resourceMode == 2 or resourceMode == 3)
            resourceEndSw:SetShown(resourceMode == 3)
            resourceStartLbl:SetShown(resourceMode == 2 or resourceMode == 3)
            resourceEndLbl:SetShown(resourceMode == 3)
        end

        -- Health Bar Color
        SecLabel(f, "Health Bar Fill", 10, UIY(-61, -539))
        local _, refreshHealthMode, healthRow = MakeOptionRow(f, BAR_COLOR_NAMES, UIY(-77, -555),
            function() return db[pre.."HealthColorMode"] or 1 end,
            function(v) db[pre.."HealthColorMode"] = v end,
            function()
                UpdateBarSwatchVisibility()
                ABP:RefreshAllBarColors()
            end,
            { maxWidth = slW - 78 })
        refreshHealthClassColor = function() end
        local hSwX = healthRow.right + 10
        healthStartSw = MakeColorSwatch(f, hSwX, UIY(-77, -555),
            function() return db[pre.."HealthR"] or 0.0, db[pre.."HealthG"] or 0.85, db[pre.."HealthB"] or 0.15, 1 end,
            function(r, g, b) SetColorTriplet("Health", r, g, b) end,
            nil, "S")
        healthStartLbl = healthStartSw.caption
        healthEndSw = MakeColorSwatch(f, hSwX + 34, UIY(-77, -555),
            function() return db[pre.."HealthER"] or 0.0, db[pre.."HealthEG"] or 0.45, db[pre.."HealthEB"] or 0.0, 1 end,
            function(r, g, b) SetColorTriplet("HealthE", r, g, b) end,
            nil, "E")
        healthEndLbl = healthEndSw.caption

        -- Resource Bar Color
        SecLabel(f, "Resource Bar Fill", 10, UIY(-109, -587))
        local _, refreshResourceMode, resourceRow = MakeOptionRow(f, BAR_COLOR_NAMES, UIY(-125, -603),
            function() return db[pre.."ResourceColorMode"] or 1 end,
            function(v) db[pre.."ResourceColorMode"] = v end,
            function()
                UpdateBarSwatchVisibility()
                ABP:RefreshAllBarColors()
            end,
            { maxWidth = slW - 78 })
        refreshResourceClassColor = function() end
        local rSwX = resourceRow.right + 10
        resourceStartSw = MakeColorSwatch(f, rSwX, UIY(-125, -603),
            function() return db[pre.."ResourceR"] or 0.0, db[pre.."ResourceG"] or 0.55, db[pre.."ResourceB"] or 1.0, 1 end,
            function(r, g, b) SetColorTriplet("Resource", r, g, b) end,
            nil, "S")
        resourceStartLbl = resourceStartSw.caption
        resourceEndSw = MakeColorSwatch(f, rSwX + 34, UIY(-125, -603),
            function() return db[pre.."ResourceER"] or 0.0, db[pre.."ResourceEG"] or 0.25, db[pre.."ResourceEB"] or 0.85, 1 end,
            function(r, g, b) SetColorTriplet("ResourceE", r, g, b) end,
            nil, "E")
        resourceEndLbl = resourceEndSw.caption
        UpdateBarSwatchVisibility()

        ---------- Bar Media -------------------------------------------------
        local barTextureLabel = SecLabel(f, "Gradient Fill Texture", 10, -635)
        local barTextureButtons, rfrBarTexture = MakeOptionRow(f, BAR_TEXTURE_NAMES, -651,
            function() return db[pre.."BarTexture"] or 1 end,
            function(v) db[pre.."BarTexture"] = v end,
            function() ABP:RefreshAllBarColors() end,
            { maxWidth = slW - 12, buttonW = 62, gap = 4 })
        refreshBarTexture = rfrBarTexture
        SetWidgetsShown({ barTextureLabel, unpack(barTextureButtons) }, showClassicFrameOptions)

        ---------- Bar Effects (within Bars group) ---------------------------
        SecLabel(f, "Bar Effects", 10, UIY(-157, -683))
        local _, rfrBarEffects = MakeToggleChipRow(f, {
            {
                label = "Gloss",
                getValue = function() return db[pre.."BarGloss"] ~= false end,
                setValue = function(v) db[pre.."BarGloss"] = v end,
                onClick = function() ABP:RefreshAllBarColors() end,
            },
            {
                label = "Shine",
                getValue = function() return db[pre.."BarShine"] or false end,
                setValue = function(v) db[pre.."BarShine"] = v end,
                onClick = function() ABP:RefreshAllBarColors() end,
            },
            {
                label = "Shadow",
                getValue = function() return db[pre.."BarShadow"] or false end,
                setValue = function(v) db[pre.."BarShadow"] = v end,
                onClick = function() ABP:RefreshAllBarColors() end,
            },
            {
                label = "Glow",
                getValue = function() return db[pre.."BarGlow"] or false end,
                setValue = function(v) db[pre.."BarGlow"] = v end,
                onClick = function() ABP:RefreshAllBarColors() end,
            },
        }, UIY(-173, -699), { startX = 10, gap = 6 })
        refreshBarEffects = rfrBarEffects

        ---------- NAME group ------------------------------------------------
        GroupDivider(f, "Name", 10, UIY(-207, -733), slW)

        ---------- Name Highlight / Text Colors ------------------------------
        local nameHighlightSw, nameTextSw
        local function UpdateNameSwatchVisibility()
            nameHighlightSw:SetShown((db[pre.."NameHighlightMode"] or 1) == 4)
            nameTextSw:SetShown((db[pre.."NameTextMode"] or 1) == 2)
        end

        SecLabel(f, "Name Highlight", 10, UIY(-233, -759))
        local _, refreshNameHighlightToggle, nameHighlightRow = MakeOptionRow(f, NAME_HIGHLIGHT_NAMES, UIY(-249, -775),
            function() return db[pre.."NameHighlightMode"] or 1 end,
            function(v) db[pre.."NameHighlightMode"] = v end,
            function()
                UpdateNameSwatchVisibility()
                ABP:RefreshAllNameStyles()
            end,
            { maxWidth = slW - 34 })
        nameHighlightSw = MakeColorSwatch(f, nameHighlightRow.right + 8, UIY(-249, -775),
            function()
                return db[pre.."NameHighlightR"] or 0, db[pre.."NameHighlightG"] or 0,
                       db[pre.."NameHighlightB"] or 0, db[pre.."NameHighlightA"] or 0.45
            end,
            function(r, g, b, a)
                db[pre.."NameHighlightR"], db[pre.."NameHighlightG"], db[pre.."NameHighlightB"], db[pre.."NameHighlightA"] = r, g, b, a
            end,
            function() ABP:RefreshAllNameStyles() end)

        SecLabel(f, "Name / Level Text Color", 10, UIY(-281, -807))
        local _, refreshNameTextMode, nameTextRow = MakeOptionRow(f, NAME_TEXT_NAMES, UIY(-297, -823),
            function() return db[pre.."NameTextMode"] or 1 end,
            function(v) db[pre.."NameTextMode"] = v end,
            function()
                UpdateNameSwatchVisibility()
                ABP:RefreshAllNameStyles()
            end,
            { maxWidth = slW - 34 })
        nameTextSw = MakeColorSwatch(f, nameTextRow.right + 8, UIY(-297, -823),
            function()
                return db[pre.."NameTextR"] or 0.82, db[pre.."NameTextG"] or 0.85,
                       db[pre.."NameTextB"] or 0, 1
            end,
            function(r, g, b)
                db[pre.."NameTextR"], db[pre.."NameTextG"], db[pre.."NameTextB"] = r, g, b
            end,
            function() ABP:RefreshAllNameStyles() end)
        UpdateNameSwatchVisibility()

        -- X position for the right column of the 2-column toggle grid.
        -- slW ≈ 368 px; col2 starts at roughly the midpoint.
        local col2X = math.floor(slW / 2) + 10

        ---------- MISC group ------------------------------------------------
        if not compactClassicOptions then
            GroupDivider(f, "Misc", 10, -857, slW)
        end

        ---------- Toggle grid (2-per-row) -----------------------------------
        -- Row 1 (y = -883 / -899):
        --   col1: Hide PvP / Prestige Badge
        --   col2: Hide Portrait Icons (player) | Idle Animations (others)
        -- Player row 2 (y = -931 / -947):
        --   col1: Hide Rested Indicator
        --   col2: Idle Animations
        -- Player row 3 (y = -979 / -995):
        --   col1: Combat Numbers
        local refreshHideEmblem      = function() end
        local refreshHideRoleIcon    = function() end
        local refreshHideRested      = function() end
        local refreshHideStatusGlow  = function() end
        local refreshShowCombatText  = function() end
        local refreshIdle            = function() end

        if not self.isClassicClient then
            -- Row 1, col 1 — Hide PvP badge (all tabs)
            if pre ~= "pet" then
                SecLabel(f, "Hide PvP / Prestige Badge", 10, -883)
                local _, rfr1 = MakeToggle(f, -899,
                    function()  return db[pre.."HideEmblem"] or false  end,
                    function(v) db[pre.."HideEmblem"] = v; ABP:FlushEmblemHide(pre) end)
                refreshHideEmblem = rfr1
            end

            if pre == "player" then
                -- Row 1, col 2 — Hide Portrait Icons (player only)
                SecLabel(f, "Hide Portrait Icons", col2X, -883)
                local _, rfr2 = MakeToggle(f, -899,
                    function()  return db.playerHideRoleIcon or false  end,
                    function(v)
                        db.playerHideRoleIcon = v
                        ABP:FlushRoleIconHide()
                        ABP:FlushCornerIconHide()
                    end, col2X)
                refreshHideRoleIcon = rfr2

                -- Row 2, col 1 — Hide Rested Indicator (player only)
                SecLabel(f, "Hide Rested Indicator", 10, -931)
                local _, rfr3 = MakeToggle(f, -947,
                    function()  return db.playerHideRested or false  end,
                    function(v) db.playerHideRested = v; ABP:FlushRestedHide() end)
                refreshHideRested = rfr3

                -- Row 2, col 2 — Idle Animations (player)
                SecLabel(f, "Idle Animations", col2X, -931)
                local _, rfr4 = MakeToggle(f, -947,
                    function()  return db[pre.."Idle"] or false  end,
                    function(v) db[pre.."Idle"] = v; pBox:Refresh() end, col2X)
                refreshIdle = rfr4

                -- Row 3, col 1 — Combat Numbers (player only)
                SecLabel(f, "Combat Numbers", 10, -979)
                local _, rfr5 = MakeToggle(f, -995,
                    function()  return db.playerShowCombatText ~= false  end,
                    function(v)
                        db.playerShowCombatText = v
                        ABP:ApplyPlayerCombatTextSetting()
                    end)
                refreshShowCombatText = rfr5

                -- Row 3, col 2 — Native status glow (independent of rested ZZZ).
                SecLabel(f, "Hide Status Glow", col2X, -979)
                local _, rfr6 = MakeToggle(f, -995,
                    function() return db.playerHideStatusGlow or false end,
                    function(v) db.playerHideStatusGlow = v; ABP:FlushStatusGlowHide() end, col2X)
                refreshHideStatusGlow = rfr6
            else
                -- Row 1, col 2 — Idle Animations (target / focus / party)
                local idleX = (pre == "pet") and 10 or col2X
                SecLabel(f, "Idle Animations", idleX, -883)
                local _, rfr2 = MakeToggle(f, -899,
                    function()  return db[pre.."Idle"] or false  end,
                    function(v) db[pre.."Idle"] = v; pBox:Refresh() end, idleX)
                refreshIdle = rfr2
            end
        end

        ---------- Class Resource Row (Player only) --------------------------
        local refreshClassPowerEnabled = function() end
        local refreshClassPowerHideBlizzard = function() end
        local refreshUseCustomRunes = function() end
        local refreshRuneTimers = function() end
        local refreshRuneStyle = function() end
        local refreshComboStyle = function() end
        local refreshClassPowerShape = function() end
        local classPowerSizeSl, classPowerSpacingSl, classPowerBorderSizeSl, classPowerXOffsetSl, classPowerYOffsetSl, runeShadeSl
        if showClassResourceSettings then
            local classResourceLabel = "Class Resource Row"
            if isDeathKnightSettings then
                classResourceLabel = "Death Knight Runes"
            elseif isRogueSettings then
                classResourceLabel = "Rogue Combo Points"
            elseif playerClassTag == "DRUID" then
                classResourceLabel = "Druid Combo Points"
            end

            -- Enabling the custom row automatically hides the native bar (and vice
            -- versa) so the two never overlap.  playerClassPowerHideBlizzard is
            -- kept in sync rather than exposed as a separate toggle.
            --
            -- DK toggle layout (2-column, all ON/OFF items together above sliders):
            --   Row 1  y=-1055/-1071 : classResourceLabel (col1) | Use Custom Runes (col2)
            --   Row 2  y=-1101/-1117 : Show Rune Timers   (col1) |
            local crCol2X = math.floor(slW / 2) + 10

            GroupDivider(f, "Class Resource Bar", 10, -1029, slW)

            SecLabel(f, classResourceLabel, 10, -1055)
            local _, rfrEnabled = MakeToggle(f, -1071,
                function() return db.playerClassPowerEnabled ~= false end,
                function(v)
                    db.playerClassPowerEnabled      = v
                    db.playerClassPowerHideBlizzard = v   -- always in sync
                    ABP:RefreshPlayerClassPower()
                    ABP:UpdateBlizzardClassPowerVisibility()
                end)
            refreshClassPowerEnabled = rfrEnabled

            local iconSizeY = -1101
            if isDeathKnightSettings then
                -- Row 1 col 2: Use Custom Runes
                SecLabel(f, "Use Custom Runes", crCol2X, -1055)
                local _, rfrUseCustomRunes = MakeToggle(f, -1071,
                    function() return db.playerUseCustomRunes ~= false end,
                    function(v)
                        db.playerUseCustomRunes = v
                        ABP:RefreshPlayerClassPower()
                        ABP:UpdateBlizzardClassPowerVisibility()
                    end, crCol2X)
                refreshUseCustomRunes = rfrUseCustomRunes

                -- Row 2: Show Rune Timers (grouped with other ON/OFF controls)
                SecLabel(f, "Show Rune Timers", 10, -1101)
                local _, rfrRuneTimers = MakeToggle(f, -1117,
                    function() return db.playerRuneTimerText ~= false end,
                    function(v)
                        db.playerRuneTimerText = v
                        ABP:UpdatePlayerClassPowerTimerText()
                end)
                refreshRuneTimers = rfrRuneTimers

                iconSizeY = -1147
            end

            -- curY cursor: buttons first, sliders after (keeps totals the same so eY is unchanged)
            local curY = iconSizeY

            -- BUTTON-TYPE CONTROLS (grouped together)
            GroupDivider(f, "Class Resource Options", 10, curY, slW)
            curY = curY - 28

            SecLabel(f, "Icon Shape", 10, curY)
            local _, rfrClassPowerShape = MakeOptionRow(f, CLASS_POWER_SHAPE_NAMES, curY - 16,
                function() return db.playerClassPowerShape or 1 end,
                function(v) db.playerClassPowerShape = v end,
                function() ABP:RefreshPlayerClassPower() end,
                { maxWidth = slW - 12, buttonW = 92, gap = 6 })
            refreshClassPowerShape = rfrClassPowerShape
            curY = curY - 64

            if isDeathKnightSettings then
                SecLabel(f, "Rune Style", 10, curY)
                local _, rfrRuneStyle = MakeOptionRow(f, RUNE_STYLE_NAMES, curY - 16,
                    function() return db.playerRuneStyle or 1 end,
                    function(v) db.playerRuneStyle = v end,
                    function() ABP:RefreshPlayerClassPower() end,
                    { maxWidth = slW - 16, buttonW = 56, gap = 4 })
                refreshRuneStyle = rfrRuneStyle
                curY = curY - 64
            elseif isRogueSettings then
                SecLabel(f, "Combo Style", 10, curY)
                local _, rfrComboStyle = MakeOptionRow(f, COMBO_STYLE_NAMES, curY - 16,
                    function() return db.playerComboPointStyle or 1 end,
                    function(v) db.playerComboPointStyle = v end,
                    function() ABP:RefreshPlayerClassPower() end,
                    { maxWidth = slW - 12, buttonW = 68, gap = 4 })
                refreshComboStyle = rfrComboStyle
                curY = curY - 64
            end

            -- SLIDER CONTROLS (grouped together)
            GroupDivider(f, "Class Resource Layout", 10, curY, slW)
            curY = curY - 28

            SecLabel(f, "Icon Size", 10, curY)
            classPowerSizeSl = MakeSlider(f, 12, 28, db.playerClassPowerSize or 18, slW, function(val)
                db.playerClassPowerSize = val
                ABP:RefreshPlayerClassPower()
            end)
            classPowerSizeSl:SetPoint("TOPLEFT", 10, curY - 18)
            curY = curY - 64

            SecLabel(f, "Icon Spacing", 10, curY)
            classPowerSpacingSl = MakeSlider(f, 0, 10, db.playerClassPowerSpacing or 4, slW, function(val)
                db.playerClassPowerSpacing = val
                ABP:RefreshPlayerClassPower()
            end)
            classPowerSpacingSl:SetPoint("TOPLEFT", 10, curY - 18)
            curY = curY - 64

            SecLabel(f, "Icon Border Size", 10, curY)
            classPowerBorderSizeSl = MakeSlider(f, 0, 6, db.playerClassPowerBorderSize or 1, slW, function(val)
                db.playerClassPowerBorderSize = val
                ABP:RefreshPlayerClassPower()
            end)
            classPowerBorderSizeSl:SetPoint("TOPLEFT", 10, curY - 18)
            curY = curY - 64

            SecLabel(f, "Row X Offset", 10, curY)
            classPowerXOffsetSl = MakeSlider(f, -80, 80, db.playerClassPowerXOffset or 0, slW, function(val)
                db.playerClassPowerXOffset = val
                ABP:RefreshPlayerClassPower()
            end)
            classPowerXOffsetSl:SetPoint("TOPLEFT", 10, curY - 18)
            curY = curY - 64

            SecLabel(f, "Row Y Offset", 10, curY)
            classPowerYOffsetSl = MakeSlider(f, -30, 12, db.playerClassPowerYOffset or -6, slW, function(val)
                db.playerClassPowerYOffset = val
                ABP:RefreshPlayerClassPower()
            end)
            classPowerYOffsetSl:SetPoint("TOPLEFT", 10, curY - 18)
            curY = curY - 64

            if isDeathKnightSettings then
                SecLabel(f, "Cooldown Shade", 10, curY)
                runeShadeSl = MakeSlider(f, 12, 80, db.playerRuneCooldownShade or 38, slW, function(val)
                    db.playerRuneCooldownShade = val
                    ABP:RefreshPlayerClassPower()
                end)
                runeShadeSl:SetPoint("TOPLEFT", 10, curY - 18)
            end
        end

        -- Vertical offset pushing Camera Zoom / X-Y sliders below the toggle grid
        -- and class-resource section above.
        --   All non-classic tabs:  toggle row 1 present → base 291 (243 + 48)
        --   Player tab:            extra toggle rows 2-3 → +96 px additional
        --   Plus class-resource section height when present.
        local eY = 0
        if not self.isClassicClient then
            local playerSettingsOffset = 96   -- two extra toggle rows on the player tab
            if showClassResourceSettings then
                playerSettingsOffset = playerSettingsOffset + (isDeathKnightSettings and 730 or 620)
            end
            eY = 597 + ((pre == "player") and playerSettingsOffset or 0)
        end

        ---------- Position group --------------------------------------------
        GroupDivider(f, "Portrait Position & Size", 10, UIY(-347, -356 - eY), slW)

        ---------- Camera Zoom -----------------------------------------------
        SecLabel(f, "Camera Zoom  (100 = head / 10 = full body)", 10, UIY(-373, -382 - eY))
        local zSl = MakeSlider(f, 10, 100, db[pre.."Zoom"] or 75, slW, function(val)
            db[pre.."Zoom"] = val; ABP:RefreshAll(); pBox:Refresh()
        end)
        zSl:SetPoint("TOPLEFT", 10, UIY(-405, -414 - eY))

        ---------- X Offset --------------------------------------------------
        SecLabel(f, "X Offset     < left   |   right >", 10, UIY(-451, -460 - eY))
        local xSl = MakeSlider(f, -30, 30, db[t.xKey] or 0, slW, function(val)
            db[t.xKey] = val; ABP:RefreshAll(); pBox:Refresh()
        end)
        xSl:SetPoint("TOPLEFT", 10, UIY(-483, -492 - eY))

        ---------- Y Offset --------------------------------------------------
        SecLabel(f, "Y Offset     v down   |   up  ^", 10, UIY(-529, -538 - eY))
        local ySl = MakeSlider(f, -30, 30, db[t.yKey] or 0, slW, function(val)
            db[t.yKey] = val; ABP:RefreshAll(); pBox:Refresh()
        end)
        ySl:SetPoint("TOPLEFT", 10, UIY(-561, -570 - eY))

        ---------- Portrait Size ---------------------------------------------
        SecLabel(f, "Portrait Size  (0 = full, 30 = most inset)", 10, UIY(-607, -616 - eY))
        HDivider(f, 10, UIY(-621, -630 - eY), slW)
        local szSl = MakeSlider(f, 0, 30, db[t.sizeKey] or 5, slW, function(val)
            db[t.sizeKey] = val; ABP:RefreshAll(); pBox:Refresh()
        end)
        szSl:SetPoint("TOPLEFT", 10, UIY(-653, -662 - eY))

        ---------- Sync on tab open ------------------------------------------
        syncFuncs[i] = function()
            refreshBg()
            refreshShape()
            refreshBorderC()
            refreshBarBC()
            refreshHealthMode()
            refreshResourceMode()
            refreshNameHighlightToggle()  -- name kept from toggle era; refreshes the option row
            refreshNameTextMode()
            refreshHealthClassColor()
            refreshResourceClassColor()
            refreshBarEffects()
            refreshBarTexture()
            refreshHideEmblem()
            refreshHideRoleIcon()
            refreshHideRested()
            refreshHideStatusGlow()
            refreshShowCombatText()
            refreshClassPowerEnabled()
            refreshClassPowerHideBlizzard()
            refreshUseCustomRunes()
            refreshRuneTimers()
            refreshRuneStyle()
            refreshComboStyle()
            refreshClassPowerShape()
            refreshIdle()
            zSl:Sync(db[pre.."Zoom"] or 75)
            xSl:Sync(db[t.xKey] or 0)
            ySl:Sync(db[t.yKey] or 0)
            szSl:Sync(db[t.sizeKey] or 5)
            portraitBorderSizeSl:Sync(db[pre.."BorderSize"] or 2)
            barBorderSizeSl:Sync(db[pre.."BarBorderSize"] or 1)
            barLengthSl:Sync(db[pre.."BarLength"] or 0)
            barHeightSl:Sync(db[pre.."BarHeight"] or 0)
            if classPowerSizeSl then classPowerSizeSl:Sync(db.playerClassPowerSize or 18) end
            if classPowerSpacingSl then classPowerSpacingSl:Sync(db.playerClassPowerSpacing or 4) end
            if classPowerBorderSizeSl then classPowerBorderSizeSl:Sync(db.playerClassPowerBorderSize or 1) end
            if classPowerXOffsetSl then classPowerXOffsetSl:Sync(db.playerClassPowerXOffset or 0) end
            if classPowerYOffsetSl then classPowerYOffsetSl:Sync(db.playerClassPowerYOffset or -6) end
            if runeShadeSl then runeShadeSl:Sync(db.playerRuneCooldownShade or 38) end
            sw:SetShown(showClassicFrameOptions and (db[pre.."Bg"] or 1) == 4)
            bsw:SetShown(showClassicFrameOptions and (db[pre.."BorderC"] or 1) == 5)
            bbsw:SetShown(showClassicFrameOptions and (db[pre.."BarBC"] or 1) == 4)
            bbswTex:SetColorTexture(db[pre.."BarBR"] or 0.82, db[pre.."BarBG"] or 0.85, db[pre.."BarBB"] or 0.90, 1)
            bswTex:SetColorTexture(db[pre.."BorderR"] or 0.82, db[pre.."BorderG"] or 0.85, db[pre.."BorderB"] or 0.90, 1)
            healthStartSw:Refresh()
            healthEndSw:Refresh()
            resourceStartSw:Refresh()
            resourceEndSw:Refresh()
            nameHighlightSw:Refresh()
            nameTextSw:Refresh()
            UpdateBarSwatchVisibility()
            UpdateNameSwatchVisibility()
            pBox:Refresh()
        end
    end

    --------------------------------------------------------------------------
    -- Profiles tab  (final tab)
    --------------------------------------------------------------------------
    do
        local profileTabIndex = #TAB_NAMES
        local f = tabFrames[profileTabIndex].content

        SecLabel(f, "Appearance", 10, -8)
        local _, refreshAppearance = MakeOptionRow(f, {"Default", "Forever"}, -32,
            function() return db.settingsAppearance == "forever" and 2 or 1 end,
            function(value)
                db.settingsAppearance = value == 2 and "forever" or "default"
                ABP:ApplySettingsAppearance()
            end)
        panel.RefreshAppearanceControls = refreshAppearance
        HDivider(f, 10, -68, PW - 40)

        SecLabel(f, "Profiles", 10, -90)
        HDivider(f, 10, -104, PW - 20)

        -- Helper: create a thin 1-px horizontal rule inside the profiles pane
        local function PDivider(yTop)
            HDivider(f, 10, yTop, PW - 40)
        end

        -- ── Save current settings ──────────────────────────────────────────
        SecLabel(f, "Save current settings as:", 10, -118)

        -- EditBox for profile name
        local eb = CreateFrame("EditBox", "ABPProfileNameBox", f, "BackdropTemplate")
        eb:SetSize(260, 22)
        eb:SetPoint("TOPLEFT", 10, -136)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(48)
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetFont(ABP_UI_FONT, 12, "")
        ThemeColor(eb, "SetTextColor", SILVER, 1)
        eb:SetTextInsets(8, 8, 0, 0)
        ApplyBackdrop(eb)
        ThemeColor(eb, "SetBackdropColor", Appearance.palette.field)
        ThemeColor(eb, "SetBackdropBorderColor", STEEL, 0.90)
        eb:SetText("")

        local saveBtn = MakeBtn(f, 80, 22, "Save")
        saveBtn:SetPoint("LEFT", eb, "RIGHT", 6, 0)
        saveBtn:SetScript("OnClick", function()
            local name = eb:GetText()
            local saved = ABP:SaveProfile(name)
            if saved then
                eb:SetText("")
                -- Rebuild the list shown in the scroll area
                if f.RefreshList then f:RefreshList() end
            end
        end)

        PDivider(-166)

        -- ── Saved profiles list ────────────────────────────────────────────
        SecLabel(f, "Saved Profiles", 10, -176)

        -- Scrollable list container
        local LIST_TOP    = -196
        local ROW_H       = 26
        local LIST_HEIGHT = PH - 242   -- approx usable height

        local scrollFrame = CreateFrame("ScrollFrame", nil, f)
        scrollFrame:SetPoint("TOPLEFT",     10, LIST_TOP)
        scrollFrame:SetPoint("BOTTOMRIGHT", -10, 10)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(PW - 40)
        scrollChild:SetHeight(1)   -- grows dynamically
        scrollFrame:SetScrollChild(scrollChild)

        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local cur = self:GetVerticalScroll()
            local max = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * ROW_H)))
        end)

        -- Pool of row frames (reused on refresh)
        local rows = {}
        local function GetRow(idx)
            if not rows[idx] then
                local row = CreateFrame("Frame", nil, scrollChild)
                row:SetHeight(ROW_H)
                row:SetPoint("TOPLEFT",  0, -(idx - 1) * ROW_H)
                row:SetPoint("TOPRIGHT", 0, -(idx - 1) * ROW_H)

                -- Alternating background stripe
                local stripe = row:CreateTexture(nil, "BACKGROUND")
                stripe:SetAllPoints()
                if idx % 2 == 0 then
                    ThemeColor(stripe, "SetColorTexture", Appearance.palette.field, 0.62)
                else
                    ThemeColor(stripe, "SetColorTexture", Appearance.palette.panel, 0.68)
                end
                row.stripe = stripe

                -- Profile name label
                local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                lbl:SetPoint("LEFT", 6, 0)
                lbl:SetPoint("RIGHT", -168, 0)
                lbl:SetJustifyH("LEFT")
                ThemeColor(lbl, "SetTextColor", SILVER, 1)
                lbl:SetFont(ABP_UI_FONT, 11, "")
                row.lbl = lbl

                -- Load button
                local loadBtn = MakeBtn(row, 72, 20, "Load")
                loadBtn:SetPoint("RIGHT", -84, 0)
                row.loadBtn = loadBtn

                -- Delete button
                local delBtn = MakeBtn(row, 72, 20, "Delete")
                delBtn:SetPoint("RIGHT", -4, 0)
                delBtn.label:SetTextColor(1, 0.40, 0.40, 1)
                Appearance.colors[delBtn.label] = nil -- Keep the destructive action red in both skins.
                row.delBtn = delBtn

                rows[idx] = row
            end
            return rows[idx]
        end

        -- Refresh list: rebuild visible rows from current profile names
        function f:RefreshList()
            local names = ABP:GetProfileNames()
            local count = #names

            -- Resize scroll child to fit all rows
            scrollChild:SetHeight(math.max(1, count * ROW_H))

            -- Show / populate used rows
            for i, name in ipairs(names) do
                local row = GetRow(i)
                row.lbl:SetText(name)
                row.loadBtn:SetScript("OnClick", function()
                    ABP:LoadProfile(name)
                    -- Sync all unit-tab sliders/buttons to reflect loaded values
                    for j = 1, #tabDefs do
                        if syncFuncs[j] then syncFuncs[j]() end
                    end
                end)
                row.delBtn:SetScript("OnClick", function()
                    ABP:DeleteProfile(name)
                    f:RefreshList()
                end)
                row:Show()
            end

            -- Hide unused rows
            for i = count + 1, #rows do
                rows[i]:Hide()
            end

            -- Empty-state message
            if not f.emptyMsg then
                f.emptyMsg = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                f.emptyMsg:SetPoint("TOP", scrollFrame, "TOP", 0, -16)
                ThemeColor(f.emptyMsg, "SetTextColor", Appearance.palette.muted, 1)
                f.emptyMsg:SetFont(ABP_UI_FONT, 12, "")
                f.emptyMsg:SetText("No profiles saved yet.")
            end
            f.emptyMsg:SetShown(count == 0)
        end

        -- Sync function called when tab is selected
        syncFuncs[profileTabIndex] = function()
            refreshAppearance()
            f:RefreshList()
        end
    end

    --------------------------------------------------------------------------
    panel:SetScript("OnShow", function() SelectTab(1) end)
    self.settingsPanel = panel
end

function ABP:ToggleSettings()
    if not self.settingsPanel then
        self:BuildSettingsPanel()
    end
    local p = self.settingsPanel
    if p:IsShown() then p:Hide() else p:Show() end
end

-------------------------------------------------------------------------------
-- Slash command
-------------------------------------------------------------------------------
SLASH_ABP1 = "/abp"
SlashCmdList["ABP"] = function(msg)
    -- Copy this line into support reports to identify the addon and client.
    if type(msg) == "string" and msg:match("^%s*(.-)%s*$"):lower() == "version" then
        local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        local installedVersion = getMetadata and getMetadata("AnimatedBlizzPortrait", "Version") or "1.2.13"
        local clientVersion, clientBuild = "unknown", "unknown"
        if type(GetBuildInfo) == "function" then clientVersion, clientBuild = GetBuildInfo() end
        print("Animated Blizzard Portraits " .. tostring(installedVersion) .. " | WoW " .. tostring(clientVersion) .. " (build " .. tostring(clientBuild) .. ")")
        return
    end

    if not ABP.db then
        print("|cffff4444ABP:|r not yet initialized — wait for login.")
        return
    end
    local cmd = msg and msg:lower():match("^(%S+)") or ""
    if cmd == "debug" then
        local function DumpPortrait(tex, p)
            local px, py = tex:GetCenter()
            local pw = math.max(tex:GetWidth(), tex:GetHeight())
            local parent = tex:GetParent()
            local rings  = p.blizzRings and #p.blizzRings or -1
            print(string.format("|cffffff00ABP [%s]|r parent=%s size=%.0f rings=%d",
                p.unit, tostring(parent:GetName() or parent:GetObjectType()), pw, rings))

            local function DumpParent(fr, lbl)
                print("  |cffaaaaaa" .. lbl .. ":|r")
                for i = 1, select("#", fr:GetRegions()) do
                    local r = select(i, fr:GetRegions())
                    if r.GetCenter then
                        local rx, ry = r:GetCenter()
                        if rx and ry then
                            local dist = ((rx-px)^2 + (ry-py)^2)^0.5
                            if dist < pw * 3 then
                                local rw    = (r.GetWidth    and r:GetWidth())    or 0
                                local layer = (r.GetDrawLayer and r:GetDrawLayer()) or "?"
                                local atlas = (r.GetAtlas    and r:GetAtlas())    or ""
                                local tp    = (r.GetTexture  and tostring(r:GetTexture())) or ""
                                print(string.format("    [%d] %s dist=%.0f w=%.0f atlas=%q tex=%q",
                                    i, layer, dist, rw, atlas, tp))
                            end
                        end
                    end
                end
            end

            DumpParent(parent, "parent=" .. tostring(parent:GetName() or "?"))
            if parent:GetParent() then
                local gp = parent:GetParent()
                DumpParent(gp, "grandparent=" .. tostring(gp:GetName() or "?"))
            end
            for _, child in ipairs({ parent:GetChildren() }) do
                local cx, cy = child.GetCenter and child:GetCenter()
                if cx and cy and ((cx-px)^2+(cy-py)^2)^0.5 < pw * 2 then
                    DumpParent(child, "child=" .. tostring(child:GetName() or child:GetObjectType()))
                end
            end
        end

        -- Dump ALL tracked portraits so we can find the main PlayerFrame one
        local count = 0
        for tex, p in pairs(ABP.portraits) do
            DumpPortrait(tex, p)
            count = count + 1
        end
        if count == 0 then print("|cffffff00ABP Debug:|r No portraits tracked yet.") end
        return
    end

    if cmd == "bartest" then
        -- Test bar finding and coloring for all units.  Type /abp bartest in chat.
        local p = "|cffffff00ABP Bar Test:|r "
        for _, unit in ipairs({"player","pet","target","focus","party1","party2"}) do
            local hBar, rBar = GetUnitBarFrames(unit)
            if hBar or rBar then
                local hn = hBar and (hBar:GetName() or "(unnamed)") or "nil"
                local rn = rBar and (rBar:GetName() or "(unnamed)") or "nil"
                print(p .. unit .. "  health=" .. hn .. "  resource=" .. rn)
                -- Force red on health, blue on resource so you can see it
                if hBar then
                    hBar:SetStatusBarColor(1, 0, 0, 1)
                end
                if rBar then
                    rBar:SetStatusBarColor(0, 0.5, 1, 1)
                end
            else
                print(p .. unit .. "  |cffff4444NOT FOUND|r")
            end
        end
        print(p .. "UnitFrameHealthBar_Update exists: " .. tostring(UnitFrameHealthBar_Update ~= nil))
        print(p .. "If bars turned red/blue — coloring works!  Run /abp bartest again to restore.")
        -- Second call restores: reapply actual saved colors
        ABP:RefreshAllBarColors()
        return
    end

    if cmd == "help" then
        print("|cffffff00/abp|r commands:")
        print("  |cff00ccff/abp|r  or  |cff00ccff/abp toggle|r  — open/close the settings panel")
        print("  |cff00ccff/abp reset|r — wipe all settings and reload UI")
        print("  |cff00ccff/abp debug|r — dump portrait debug info to chat")
        print("  |cff00ccff/abp bartest|r — test health/resource bar colour detection")
        return
    elseif cmd == "toggle" then
        ABP:ToggleSettings()
        return
    elseif cmd == "reset" then
        AnimatedBlizzPortraitDB = nil
        ReloadUI()
        return
    end

    ABP:ToggleSettings()
end

-------------------------------------------------------------------------------
-- Interface Options registration
-------------------------------------------------------------------------------
do
    local reg = CreateFrame("Frame")
    reg:RegisterEvent("ADDON_LOADED")
    reg:SetScript("OnEvent", function(self, event, arg1)
        if arg1 ~= "AnimatedBlizzPortrait" then return end
        self:UnregisterAllEvents()

        local panel = CreateFrame("Frame")
        panel.name = "Animated Blizz Portrait"

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        ThemeColor(title, "SetTextColor", SILVER)
        title:SetFont(ABP_UI_FONT, 18, "")
        title:SetText("Animated Blizz Portrait")

        local btn = MakeBtn(panel, 160, 26, "Open Settings")
        btn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -18)
        btn:SetScript("OnClick", function()
            if ABP and ABP.ToggleSettings then ABP:ToggleSettings() end
        end)

        local cmds = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        cmds:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -10)
        ThemeColor(cmds, "SetTextColor", Appearance.palette.muted, 1)
        cmds:SetFont(ABP_UI_FONT, 12, "")
        cmds:SetText("/abp")

        if Settings and Settings.RegisterCanvasLayoutCategory then
            local cat = Settings.RegisterCanvasLayoutCategory(panel, "Animated Blizz Portrait", "Animated Blizz Portrait")
            Settings.RegisterAddOnCategory(cat)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
        end
    end)
end
