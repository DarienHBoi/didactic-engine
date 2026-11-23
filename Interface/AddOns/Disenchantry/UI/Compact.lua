-- The compact view renders a small presentation model of the queue head.
local _, ns = ...
local App, UI = ns.App, ns.UI

function App.GetCompactSkippedText()
    local count = ns.GetValuableSkippedCount()
    if count == 0 then return end
    return count == 1 and App.L.COMPACT_SKIPPED_ONE or string.format(App.L.COMPACT_SKIPPED_MANY, count)
end
local function content()
    local item, mode = App.queue[1], App.activeMode
    local skipped = App.GetCompactSkippedText()
    local title = item and (item.name or App.L.UNKNOWN) or App.L[mode.emptyTextKey]
    local counter = item and string.format(App.L[mode.queueTextKey], #App.queue) or ""
    if item and mode.usesItemProtection and item.bindTag then counter = counter .. "   " .. item.bindTag end
    if skipped then counter = counter == "" and skipped or counter .. "  |  " .. skipped end
    return {item=item, title=title, counter=counter,
        icon=item and (item.texture or 134400) or mode.icon() or 134400,
        preview=item and not App.db.hideDisenchantMaterials and mode.key == "disenchant" and ns.DisenchantResults.IsSupported()}
end
function App.UpdateCompactFrame()
    local bar = App.compactFrame
    if not bar or not bar:IsShown() then return end
    local model = content()
    bar.currentItem = model.item
    App.compactNameText:SetText(model.title)
    App.compactQueueText:SetText(model.counter)
    App.compactIcon:SetTexture(model.icon)
    UI.Color(App.compactNameText, model.item and model.item.quality, model.item and {1, 1, 1} or {0.7, 0.7, 0.7})
    ns.DisenchantResults.UpdateStrip(App.compactResultsStrip, model.preview and model.item or nil)
    App.compactSkipButton:SetEnabled(model.item ~= nil and not InCombatLockdown())
    if InCombatLockdown() then return end
    App.compactNameText:SetWidth(0)
    local text = math.max(App.compactNameText:GetStringWidth(), App.compactQueueText:GetStringWidth())
    local materials = model.preview and App.compactResultsStrip.contentWidth + 32 or 0
    local width = math.max(440, materials)
    bar:SetSize(width, model.preview and 150 or 116)
    local textWidth = math.min(text, width - 144)
    App.compactNameText:SetWidth(textWidth)
    App.compactQueueText:SetWidth(textWidth)
    local groupWidth = textWidth + 44
    UI.Anchor(App.compactIcon:GetParent(), {{"TOPLEFT", bar, "TOPLEFT", math.floor((width-groupWidth)/2), -38}})

end
local function savePosition(bar)
    if InCombatLockdown() then return end
    bar:StopMovingOrSizing()
    local anchor, _, relative, horizontal, vertical = bar:GetPoint()
    App.db.compactPoint = {point=anchor, relPoint=relative, x=horizontal, y=vertical}
end
local function inspect(icon)
    local item = App.compactFrame.currentItem
    if not item then return end
    GameTooltip:SetOwner(icon, "ANCHOR_TOP")
    GameTooltip:SetBagItem(item.bag, item.slot)
    if App.activeMode.key == "disenchant" then ns.DisenchantResults.AddTooltip(item) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(App.L[App.activeMode.blacklistHintKey], 0.6, 0.8, 1)
    GameTooltip:Show()
end
function App.CreateCompactFrame()
    local bar = UI.Surface(UIParent, "window", {name="Disenchantry_CompactFrame", width=440, height=150})
    bar:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=26, insets={left=7,right=7,top=7,bottom=7}})
    bar:SetBackdropColor(0.09,0.065,0.05,0.96)
    bar:SetFrameStrata("DIALOG")
    App.compactFrame = bar
    local position = App.db.compactPoint or {x=0, y=-220}
    UI.Anchor(bar, {{position.point or "CENTER", UIParent, position.relPoint or "CENTER", position.x or 0, position.y or 0}})
    for _, method in ipairs({"SetMovable", "EnableMouse", "SetClampedToScreen"}) do bar[method](bar, true) end
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() if not InCombatLockdown() then bar:StartMoving() end end)
    bar:SetScript("OnDragStop", savePosition)
    bar:Hide()
    local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
    UI.Anchor(close, {{"TOPRIGHT", -4, -4}})
    close:SetScript("OnClick", function()
        if InCombatLockdown() and bar:IsProtected() then App.Print(App.L.NOT_IN_COMBAT) else bar:Hide() end
    end)
    UI.Text(bar, "Disenchantry", "GameFontNormal", {{"TOPLEFT", 14, -12}})
    local icon
    icon, App.compactIcon = UI.Icon(bar, 36, {{"TOPLEFT", 80, -36}})
    icon:EnableMouse(true)
    UI.BindTooltip(icon, inspect)
    icon:SetScript("OnMouseUp", function(owner, mouse)
        if mouse == "RightButton" and bar.currentItem then
            UI.DismissTooltip(owner)
            App.AddItemToBlacklist(bar.currentItem, App.L.ADDED_MANUAL)
        end
    end)
    App.compactFullButton = UI.Button(bar, {key="FULL_BUTTON", width=48, height=22,
        points={{"RIGHT", close, "LEFT", -2, 0}}, compactDestination=false})
    local statistics = UI.Button(bar, {key="STATS_BUTTON", width=90, height=22,
        points={{"RIGHT", App.compactFullButton, "LEFT", -2, 0}}, click=ns.Statistics.Toggle})
    App.compactMaterialsButton = UI.Button(bar, {width=74, height=22,
        points={{"RIGHT", statistics, "LEFT", -2, 0}}, click=App.ToggleDisenchantMaterials, hint=App.L.TOGGLE_MATERIALS_HINT})
    App.compactPreviousButton = UI.Button(bar, {text="<", width=22, height=22,
        points={{"TOPLEFT", bar, "TOPLEFT", 14, -43}}, click=function() App.CycleQueuedItem(-1) end, hint=App.L.PREVIOUS_ITEM})
    App.compactNextButton = UI.Button(bar, {text=">", width=22, height=22,
        points={{"TOPRIGHT", bar, "TOPRIGHT", -14, -43}}, click=function() App.CycleQueuedItem(1) end, hint=App.L.NEXT_ITEM})
    for _, arrow in ipairs({App.compactPreviousButton, App.compactNextButton}) do
        arrow:GetFontString():SetFontObject("GameFontNormalLarge")
    end
    App.compactBlacklistButton = UI.Button(bar, {key="BLACKLIST_ITEM_BUTTON", width=126, height=26,
        points={{"TOP", bar, "TOP", 133, -80}}, click=function()
            if InCombatLockdown() then App.Print(App.L.NOT_IN_COMBAT); return end
            if UnitCastingInfo("player") or UnitChannelInfo("player") then return end
            local item = App.queue[1]
            if item then App.AddItemToBlacklist(item, App.L.ADDED_MANUAL) end
        end})
    App.compactSkipButton = UI.Button(bar, {key="SKIP_BUTTON", width=108, height=26,
        points={{"RIGHT", App.compactBlacklistButton, "LEFT", -2, 0}}, click=App.SkipQueuedItem, hint=App.L.SKIP_HINT})
    App.compactModeSelector = UI.Button(bar, {width=90, height=22,
        points={{"BOTTOMLEFT", bar, "TOPLEFT", 12, 2}}, hint=App.L.MODE_SWITCH_HINT, click=function()
            if InCombatLockdown() then App.Print(App.L.MODE_CHANGE_IN_COMBAT or App.L.NOT_IN_COMBAT); return end
            local menu = App.compactModeMenu
            menu:SetShown(not menu:IsShown())
            if menu:IsShown() then menu:Raise() end
        end})
    App.CreateCompactModeMenu()
    UI.Anchor(App.compactModeMenu, {{"BOTTOMRIGHT", App.compactModeSelector, "TOPRIGHT", 0, 6}})
    App.compactNameText = UI.Text(bar, "", "GameFontNormalLarge",
        {{"TOPLEFT", icon, "TOPRIGHT", 8, -1}})
    App.compactNameText:SetWordWrap(false)
    App.compactQueueText = UI.Text(bar, "", "GameFontHighlight",
        {{"TOPLEFT", App.compactNameText, "BOTTOMLEFT", 0, -4}})
    App.compactQueueText:SetTextColor(0.75, 0.75, 0.75)
    App.compactResultsStrip = ns.DisenchantResults.CreateStrip(bar, true)
    UI.Anchor(App.compactResultsStrip, {{"TOP", bar, "TOP", 0, -112}})
    bar:SetScript("OnHide", function()
        ns.Queue.EndSession()
        App.compactModeMenu:Hide()
    end)
    for _,button in ipairs({App.compactFullButton,statistics,App.compactMaterialsButton,App.compactSkipButton,App.compactBlacklistButton}) do
        button:SetNormalFontObject(GameFontNormal)
        button:SetHighlightFontObject(GameFontHighlight)
    end
    App.UpdateModeSurface()
end
