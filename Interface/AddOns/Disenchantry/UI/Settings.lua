-- Settings are built from control descriptors with shared read/write bindings.
local _, ns = ...
local App, UI = ns.App, ns.UI
local limits = {
    {enabled="ilvlCapEnabled", value="ilvlCap", title="ILVL_PROTECT", prompt="ILVL_BELOW", hint="ILVL_HINT", warning="ILVL_CAP_EMPTY", top=42, digits=4, width=52},
    {enabled="priceWarnEnabled", value="priceThresholdGold", title="PRICE_PROTECT", prompt="PRICE_AT_LEAST", hint="PRICE_HINT", warning="PRICE_THRESHOLD_EMPTY", top=174, digits=9, width=76},
}
local function divider(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    UI.Anchor(line, {{"TOPLEFT", 14, -y}, {"TOPRIGHT", -14, -y}})
    line:SetHeight(1)
    line:SetColorTexture(0.4, 0.4, 0.4, 0.4)
end
local function paragraph(parent, key, x, y)
    local text = UI.Text(parent, App.L[key], "GameFontDisableSmall", {{"TOPLEFT", x, -y}, {"RIGHT", parent, "RIGHT", -18, 0}})
    text:SetWordWrap(true)
    return text
end
local function threshold(parent, spec)
    local controls = {}
    local function warn()
        if App.db[spec.enabled] and not tonumber(App.db[spec.value]) then App.Print(App.L[spec.warning]) end
    end
    controls.check = UI.Check(parent, App.L[spec.title], {{"TOPLEFT", 14, -spec.top}}, function(on)
        App.db[spec.enabled] = on
        warn(); App.RefreshWorkspace()
    end)
    local label = UI.Text(parent, App.L[spec.prompt], nil, {{"TOPLEFT", 44, -spec.top - 38}})
    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    controls.input = input
    UI.Anchor(input, {{"LEFT", label, "RIGHT", spec.value == "ilvlCap" and 14 or 10, 0}})
    input:SetSize(spec.width, 20)
    input:SetAutoFocus(false)
    input:SetNumeric(true)
    input:SetMaxLetters(spec.digits)
    local function commit()
        App.db[spec.value] = tonumber(input:GetText())
        warn(); App.RefreshWorkspace()
    end
    input:SetScript("OnEditFocusLost", commit)
    input:SetScript("OnEnterPressed", function() commit(); input:ClearFocus() end)
    input:SetScript("OnEscapePressed", function() input:ClearFocus() end)
    controls.sync = function()
        controls.check:SetChecked(App.db[spec.enabled])
        input:SetText(App.db[spec.value] and tostring(App.db[spec.value]) or "")
    end
    paragraph(parent, spec.hint, 44, spec.top + 66)
    if spec.value == "ilvlCap" then
        controls.suggest = UI.Button(parent, {key="ILVL_SUGGEST", width=90, points={{"TOPRIGHT", -14, -75}}, click=function()
            local suggestion = App.GetLowestEquippedItemLevel()
            if suggestion then input:SetText(tostring(suggestion)); commit() end
        end})
    else UI.Text(parent, App.L.PRICE_GOLD, nil, {{"LEFT", input, "RIGHT", 8, 0}}) end
    return controls
end
local function languageControls(window)
    UI.Text(window, App.L.LANGUAGE, "GameFontNormal", {{"TOPLEFT", 18, -438}})
    UI.Text(window, App.L.LANGUAGE_AUTO .. " (" .. GetLocale() .. ")", nil, {{"TOPLEFT", 18, -464}})
    paragraph(window, "LANGUAGE_HINT", 18, 490)
end
function App.CreateSettingsFrame()
    local window = App.CreateStyledWindow("Disenchantry_SettingsFrame", 940, 550)
    App.settingsFrame = window
    UI.Anchor(window, {{"CENTER", UIParent, "CENTER", 0, 0}})
    window:Hide()
    window.title:SetText(App.L.SETTINGS_TITLE)
    local group = CreateFrame("Frame", nil, window)
    group:SetPoint("TOPLEFT", window, "TOPLEFT")
    group:SetSize(470, 550)
    local right = CreateFrame("Frame", nil, window)
    right:SetPoint("TOPRIGHT", window, "TOPRIGHT")
    right:SetSize(470, 550)
    local separator = window:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOP", window, "TOP", 0, -38)
    separator:SetPoint("BOTTOM", window, "BOTTOM", 0, 18)
    separator:SetWidth(1)
    separator:SetColorTexture(0.4, 0.4, 0.4, 0.4)
    App.settingsProtectionGroup = group
    App.settingsModeHint = UI.Text(window, App.L.MODE_NO_PROTECTION_SETTINGS, "GameFontNormal",
        {{"TOPLEFT", 24, -54}, {"RIGHT", group, "RIGHT", -24, 0}})
    App.settingsModeHint:SetWordWrap(true)
    local controls = {limits={}, qualities={}}
    App.settingsControls = controls
    for _, spec in ipairs(limits) do controls.limits[spec.value] = threshold(group, spec) end
    divider(group, 162); divider(group, 300)
    UI.Text(group, App.L.QUALITY_HEADER, "GameFontNormal", {{"TOPLEFT", 14, -312}})
    for index, quality in ipairs({2, 3, 4}) do
        local check = UI.Check(group, App.L["QUALITY_" .. quality] or _G["ITEM_QUALITY" .. quality .. "_DESC"],
            {{"TOPLEFT", 24, -338 - (index - 1) * 30}}, function(on)
                App.db.qualityFilter[quality] = on; App.RefreshWorkspace()
            end)
        UI.Color(check.caption, quality)
        controls.qualities[quality] = check
    end
    languageControls(right)
    ns.Hotkeys.CreateControls(right, App.CreateStyledButton)
    controls.minimap = UI.Check(right, App.L.MINIMAP_SHOW_OPTION, {{"TOPLEFT", 14, -168}}, function(show)
        App.db.minimap.hide = not show
        if App.libDBIcon then App.libDBIcon[show and "Show" or "Hide"](App.libDBIcon, "Disenchantry") end
    end)
    App.settingsMaterialsButton = UI.Button(right, {width=100, height=22,
        points={{"TOPRIGHT", right, "TOPRIGHT", -18, -168}},
        click=App.ToggleDisenchantMaterials, hint=App.L.TOGGLE_MATERIALS_HINT})
    controls.disenchantDisplay = {}
    for index, spec in ipairs({
        {key="hideDisenchantMaterials", label="SHOW_DE_MATERIALS"},
        {key="hideDisenchantChances", label="SHOW_DE_CHANCES"},
        {key="hideDisenchantValue", label="SHOW_DE_VALUE"},
    }) do
        local key = spec.key
        controls.disenchantDisplay[key] = UI.Check(right, App.L[spec.label],
            {{"TOPLEFT", 14, -202 - (index - 1) * 28}}, function(show)
                if InCombatLockdown() then
                    App.Print(App.L.NOT_IN_COMBAT)
                    controls.disenchantDisplay[key]:SetChecked(not App.db[key])
                    return
                end
                App.db[key] = not show
                GameTooltip:Hide()
                App.RefreshUI()
            end)
    end
    divider(right, 294)
    UI.Text(right, App.L.AUCTIONATOR_SOURCE, "GameFontNormal", {{"TOPLEFT", 18, -309}})
    controls.auctionator = {}
    local function syncAuctionator()
        for key, button in pairs(controls.auctionator) do
            button:SetEnabled(key ~= ns.Prices.GetAuctionatorSource())
            if key == "average" then button:SetText(string.format(App.L.AUCTIONATOR_AVERAGE, ns.Prices.GetAuctionatorAverageDays())) end
        end
    end
    for index, entry in ipairs({{"last", "AUCTIONATOR_LAST"}, {"average", "AUCTIONATOR_AVERAGE"}}) do
        local key = entry[1]
        controls.auctionator[key] = UI.Button(right, {key=entry[2], width=210, height=24,
            points={{"TOPLEFT", 18 + (index - 1) * 220, -336}}, click=function()
                if InCombatLockdown() then App.Print(App.L.NOT_IN_COMBAT); return end
                App.db.auctionatorSource = key
                ns.Prices.ClearCache()
                syncAuctionator()
                GameTooltip:Hide()
                App.RefreshWorkspace()
            end})
    end
    paragraph(right, "AUCTIONATOR_SOURCE_HINT", 18, 370)
    UI.Button(window,{text=GetLocale()=="ruRU" and "Оценка и отображение…" or "Forecast and display…",width=245,height=22,
        points={{"BOTTOMLEFT",18,12}},click=function() App.ToggleForecastPreferences() end})
    local sourceNames = {auto=GetLocale()=="ruRU" and "Авто" or "Auto", tsm="TSM DBMarket", auctionator="Auctionator"}
    local menu
    local sourceButton
    local function syncSource()
        local source = sourceNames[App.db.marketSource] or sourceNames.auto
        sourceButton:SetText((GetLocale()=="ruRU" and "Цены: " or "Prices: ") .. source .. "  v")
    end
    sourceButton = UI.Button(window, {width=175,height=22,points={{"BOTTOMRIGHT",-18,12}},click=function()
        menu:SetShown(not menu:IsShown())
    end})
    menu = UI.Surface(window, "menu", {width=175, height=84})
    menu:SetPoint("BOTTOMRIGHT", sourceButton, "TOPRIGHT", 0, 2)
    menu:SetFrameLevel(sourceButton:GetFrameLevel()+8)
    menu:EnableMouse(true)
    menu:Hide()
    for index, key in ipairs({"auto","tsm","auctionator"}) do
        UI.Button(menu, {text=sourceNames[key], width=165, height=24,
            points={{"TOP",0,-5-(index-1)*25}}, click=function()
                App.db.marketSource = key
                menu:Hide()
                syncSource()
                App.ForecastPreferencesChanged()
            end})
    end
    window:HookScript("OnHide", function() menu:Hide() end)
    for _, key in ipairs({"Disenchantry_SettingsFrame", "Disenchantry_BlacklistFrame"}) do table.insert(UISpecialFrames, key) end
    window:SetScript("OnShow", function()
        App.UpdateModeSurface()
        syncSource()
        syncAuctionator()
        for _, field in pairs(controls.limits) do field.sync() end
        for quality, check in pairs(controls.qualities) do check:SetChecked(App.db.qualityFilter[quality] ~= false) end
        for key, check in pairs(controls.disenchantDisplay) do check:SetChecked(not App.db[key]) end
        controls.minimap:SetChecked(not App.db.minimap.hide)
        App.settingsMaterialsButton:SetText(App.L[App.db.hideDisenchantMaterials and "SHOW_MATERIALS" or "HIDE_MATERIALS"])
    end)
end
function App.ToggleSettingsFrame()
    local points = {{"CENTER", UIParent, "CENTER", 0, 0}}
    UI.Toggle(App.settingsFrame, points)
end
