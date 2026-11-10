-- Forever Fishing
-- Copyright Â© 2026 Hamish336. All Rights Reserved.
-- Applies to original Forever Fishing code and assets only.
-- Blizzard-owned assets and trademarks remain property of Blizzard Entertainment.
-- Unauthorized redistribution or modification is prohibited.
local FF = _G.ForeverFishing
local function L(key) return FF.LocalizedText and FF:LocalizedText(key) or key end
-- Native wrapping also applies to single-string help, not only AddLine bodies.
local function TooltipText(text)
    GameTooltip:SetText(text,nil,nil,nil,nil,true)
end
local GOLD = { 1, 0.80, 0.39 }
local WHITE = { 0.90, 0.92, 0.92 }
local MUTED = { 0.65, 0.72, 0.74 }
local CYAN = { 0.14, 0.72, 0.82 }
local FONT = "Fonts\\2002.TTF"
local function Color(texture, r, g, b, a) texture:SetColorTexture(r, g, b, a or 1); return texture end
local function Rect(parent, x, y, w, h, r, g, b, a, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    t:SetSize(w, h)
    return Color(t, r, g, b, a)
end
local function Border(parent, x, y, w, h, color, thick)
    thick = thick or 1
    -- Each frame owns one four-edge set per border rectangle. Keep edges above
    -- that frame's BACKGROUND fill and reuse them if the layout is refreshed.
    local key = table.concat({ x, y, w, h, thick }, ":")
    parent.settingsBorderEdges = parent.settingsBorderEdges or {}
    local edges = parent.settingsBorderEdges[key]
    if not edges then
        edges = {}
        for i = 1, 4 do
            local edge = parent:CreateTexture(nil, "BORDER")
            -- The Settings window has a fractional default scale; snap its
            -- narrow bronze strokes as the Journal does for its gold edges.
            if edge.SetSnapToPixelGrid then edge:SetSnapToPixelGrid(true) end
            if edge.SetTexelSnappingBias then edge:SetTexelSnappingBias(0) end
            edges[i] = edge
        end
        parent.settingsBorderEdges[key] = edges
    end
    local r, g, b = unpack(color)
    local positions = {
        { x, y, w, thick }, { x, y + h - thick, w, thick },
        { x, y, thick, h }, { x + w - thick, y, thick, h },
    }
    for i, edge in ipairs(edges) do
        local rect = positions[i]
        edge:ClearAllPoints()
        edge:SetPoint("TOPLEFT", parent, "TOPLEFT", rect[1], -rect[2])
        edge:SetSize(rect[3], rect[4])
        Color(edge, r, g, b)
    end
end
local function Text(parent, label, x, y, w, h, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    fs:SetSize(w, h)
    if not FF:SetDisplayFont(fs, FONT, size, "") then fs:SetFont("Fonts\\FRIZQT__.TTF", size, "") end
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetTextColor(unpack(color or WHITE))
    fs:SetText(L(label))
    return fs
end
local function RegisterFocus(parent, control, y, height)
    local panel = parent.settingsOwner
    if not panel then return end
    panel.focusables[#panel.focusables + 1] = control
    control.settingsPage = parent.settingsPage
    control.settingsY, control.settingsHeight = y, height
    local focus = control:CreateTexture(nil, "OVERLAY")
    focus:SetAllPoints(control)
    focus:SetColorTexture(1, .79, .3, .14)
    focus:Hide()
    control.settingsFocusTexture = focus
end

local function InstallSettingsFocus(panel)
    function panel:SetSettingsFocus(control)
        if self.focusControl then self.focusControl.settingsFocusTexture:Hide() end
        self.focusControl = control
        if not control then return end
        control.settingsFocusTexture:Show()
        if control.settingsPage and control.settingsY then
            local offset = self.scroll:GetVerticalScroll()
            local top, bottom = control.settingsY, control.settingsY + control.settingsHeight
            if top < offset then self:SetPageScroll(top - 8)
            elseif bottom > offset + self.scroll:GetHeight() then self:SetPageScroll(bottom - self.scroll:GetHeight() + 8) end
        end
    end
    -- Browsing is mouse-driven, like Journal. A window-wide keyboard listener
    -- can claim native game bindings even when it intends to propagate them.
    -- Genuine EditBoxes and the independent binding shield own their input.
    panel:EnableKeyboard(false)
end
local function Button(parent, x, y, w, h, label, click)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    b:SetSize(w, h)
    Rect(b, 0, 0, w, h, 0.055, 0.105, 0.14, 1)
    Border(b, 0, 0, w, h, { 0.57, 0.35, 0.09 }, 2)
    Border(b, 3, 3, w - 6, h - 6, { 0.17, 0.24, 0.27 })
    b.label = Text(b, label, 7, 1, w - 14, h - 2, 14, WHITE, "CENTER")
    b.label:SetWordWrap(true)
    b:SetScript("OnEnter", function() b.label:SetTextColor(unpack(GOLD)) end)
    b:SetScript("OnLeave", function() b.label:SetTextColor(unpack(WHITE)) end)
    b:SetScript("OnClick", click)
    function b:SetText(value) self.label:SetText(L(value)) end
    function b:GetFontString() return self.label end
    RegisterFocus(parent, b, y, h)
    return b
end
function FF:CreateFishingBindingDialogButton(parent,label,width,height,click)
    local button=Button(parent,0,0,width,height,label,click)
    button.label:SetWordWrap(true)
    return button
end
local function Section(parent, label, x, y, width)
    local title = Text(parent, label, x, y, width, 27, 20, GOLD)
    local offset = math.min(width - 20, 15 + title:GetStringWidth())
    Rect(parent, x + offset, y + 17, width - offset, 1, unpack(CYAN))
end
local function Toggle(parent, x, y, w, h, label, callback, detail, tooltip, statusWords)
    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    row:SetSize(w, h)
    Rect(row, 0, 0, w, h, 0.045, 0.105, 0.14, 0.75)
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(row)
    hover:SetColorTexture(0.13, 0.26, 0.30, 0.32)
    row:SetHighlightTexture(hover)
    Border(row, 13, math.floor((h - 22) / 2), 22, 22, { 0.53, 0.33, 0.07 }, 2)
    local check = row:CreateTexture(nil, "OVERLAY")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetVertexColor(1, 0.79, 0.30)
    check:SetSize(27, 27)
    check:SetPoint("CENTER", row, "TOPLEFT", 24, -h / 2)
    row.title = Text(row, label, 48, detail and 7 or 0, w - (parent.compactSettings and 62 or (statusWords and 146 or 114)), detail and 28 or h, 16, WHITE)
    if detail then row.detail = Text(row, detail, 48, 31, w - (statusWords and 146 or 110), h - 32, 12, MUTED) end
    row.state = Text(row, L("settings.copy.off-ca79"), w - (statusWords and 94 or 59), 0, statusWords and 77 or 42, h, 15, MUTED, "RIGHT")
    if parent.compactSettings then row.state:Hide() end
    if parent.measuredSettings then row.title:SetWordWrap(true); row.state:SetWordWrap(true) end
    function row:SetState(enabled)
        check:SetShown(enabled == true)
        self.state:SetText(enabled and (statusWords and statusWords.active or L("settings.copy.on-1300"))
            or (statusWords and statusWords.inactive or L("settings.copy.off-ca79")))
        self.state:SetTextColor(unpack(enabled and GOLD or MUTED))
    end
    row:SetScript("OnClick", callback)
    if tooltip then
        row:SetScript("OnEnter", function(button)
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            if type(tooltip) == "table" then
                TooltipText(tooltip.title)
                GameTooltip:AddLine(tooltip.body, .90, .92, .92, true)
                GameTooltip:AddLine(tooltip.note, .70, .79, .84, true)
            else TooltipText(tooltip) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    RegisterFocus(parent, row, y, h)
    return row
end
local RowHeight
local function Slider(parent, x, y, w, label, min, max, step, format, change, userInputOnly)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    row:SetSize(w, 41)
    row.label = Text(row, label, 0, 0, 208, 36, 16, WHITE)
    local trackX, trackW = w - 319, 233
    local measured=parent.compactSettings or parent.measuredSettings
    local height=measured and RowHeight(parent,{label},trackX-10,41) or 41
    row:SetHeight(height)
    if measured then row.label:SetSize(trackX-10,height); row.label:SetWordWrap(true) end
    local center=height/2
    local trackY=measured and center-2.5 or 17
    local track=Rect(row, trackX, trackY, trackW, 5, 0.16, 0.31, 0.37)
    local fill = Rect(row, trackX, trackY, 1, 5, unpack(CYAN))
    local s = CreateFrame("Slider", nil, row)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", row, "TOPLEFT", trackX, measured and -(center-10) or -10)
    s:SetSize(trackW, 20)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = s:GetThumbTexture()
    thumb:SetVertexColor(1, 0.78, 0.29)
    thumb:SetSize(5, 17)
    row.value = Text(row, "", w - 78, 0, 75, 36, 15, WHITE, "RIGHT")
    row.slider = s
    function row:SetRowHeight(value)
        self:SetHeight(value); self.label:SetHeight(value); self.value:SetHeight(value)
        trackY=value/2-2.5
        track:ClearAllPoints(); track:SetPoint("TOPLEFT",self,"TOPLEFT",trackX,-trackY)
        fill:ClearAllPoints(); fill:SetPoint("TOPLEFT",self,"TOPLEFT",trackX,-trackY)
        s:ClearAllPoints(); s:SetPoint("TOPLEFT",self,"TOPLEFT",trackX,-(value/2-10))
        self.settingsHeight=value
    end
    if measured then row.value:SetHeight(height) end
    function row:Refresh(value,mixed)
        self.updating = true
        self.mixed=mixed==true
        value = math.max(min, math.min(max, tonumber(value) or min))
        s:SetValue(value)
        fill:SetWidth(math.max(1, (value - min) / (max - min) * trackW))
        fill:SetShown(not self.mixed); thumb:SetShown(not self.mixed)
        self.value:SetText(self.mixed and L("flyout.mixed") or format(value))
        self.updating = false
    end
    s:SetScript("OnValueChanged", function(_, value, userInput)
        -- Native SetValue notifications can arrive after Refresh has returned.
        -- Game audio controls must never turn display synchronization into writes.
        if row.updating or (userInputOnly and userInput ~= true) then return end
        value = math.floor(value / step + 0.5) * step
        change(value)
        row:Refresh(value)
    end)
    if parent.compactSettings and userInputOnly then s:SetScript("OnMouseUp",function()
        -- Clicking the mixed track at its existing internal value need not fire
        -- OnValueChanged. A deliberate release still applies that chosen value.
        if row.mixed and not row.updating then
            local value=math.floor((s:GetValue() or min)/step+.5)*step
            change(value); row:Refresh(value)
        end
    end) end
    row.settingsAdjust = function(direction)
        local value = math.max(min, math.min(max, (s:GetValue() or min) + direction * step))
        change(value) -- A deliberate keyboard gesture, including audio sliders.
        row:Refresh(value)
    end
    RegisterFocus(parent, row, y, height)
    return row
end
local function DropDown(panel, parent, x, y, w, h, choices, selected, change, openUp, fallbackLabel)
    local button = Button(parent, x, y, w, h, "", function() end)
    button.label:SetWidth(w-44); button.label:SetWordWrap(true)
    local arrow = Text(button, "â–¼", w - 30, 0, 19, h, 14, GOLD, "CENTER")
    local menu = CreateFrame("Frame", nil, panel)
    menu:SetClampedToScreen(true)
    menu.settingsOwner = panel.focusables and panel or nil
    menu:SetFrameLevel(panel:GetFrameLevel() + 80)
    if openUp == nil then openUp = y > 300 end
    if openUp then
        menu:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 2)
    else
        menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    end
    local heights, menuHeight = {}, 8
    for i, choice in ipairs(choices) do
        heights[i]=RowHeight(parent,{choice.label},w-30,30,14)
        menuHeight=menuHeight+heights[i]
    end
    menu:SetSize(w, menuHeight)
    Rect(menu, 0, 0, w, menuHeight, 0.035, 0.075, 0.10)
    Border(menu, 0, 0, w, menuHeight, { 0.57, 0.35, 0.09 }, 2)
    menu:Hide()
    local rows, rowY = {}, 4
    for i, choice in ipairs(choices) do
        local row = CreateFrame("Button", nil, menu)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -rowY)
        local rowHeight=heights[i]
        row:SetSize(w - 8, rowHeight)
        rowY=rowY+rowHeight
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints(row); hover:SetColorTexture(0.12, 0.27, 0.31, 0.75)
        row:SetHighlightTexture(hover)
        local title = Text(row, choice.label, 9, 0, w - 30, rowHeight, 14, WHITE)
        title:SetWordWrap(true)
        row:SetEnabled(not choice.disabled)
        if choice.disabled then hover:SetAlpha(0) end
        row:SetScript("OnClick", function()
            if choice.disabled then return end
            menu:Hide()
            change(choice.id)
            panel.openMenu = nil
            if panel.SetSettingsFocus and FF.settingsKeyboardFocus then panel:SetSettingsFocus(button) end
        end)
        RegisterFocus(menu, row, nil, rowHeight)
        rows[i] = { choice = choice, title = title, button = row }
    end
    button:SetScript("OnClick", function()
        if panel.openMenu and panel.openMenu ~= menu then panel.openMenu:Hide() end
        menu:SetShown(not menu:IsShown())
        panel.openMenu = menu:IsShown() and menu or nil
        if menu:IsShown() and FF.settingsKeyboardFocus and panel.SetSettingsFocus then panel:SetSettingsFocus(rows[1].button) end
    end)
    function button:Refresh()
        local id = selected()
        local label
        for _, row in ipairs(rows) do
            row.title:SetTextColor(unpack(row.choice.disabled and MUTED or (row.choice.id == id and GOLD or WHITE)))
            if row.choice.id == id then label = row.choice.label end
        end
        self:SetText(label or fallbackLabel or "")
    end
    button.menu = menu
    button.options = rows
    button.arrow = arrow
    button:Refresh()
    return button
end
local function Page(panel, id, height)
    local page = CreateFrame("Frame", nil, panel.content)
    page:SetPoint("TOPLEFT", panel.content, "TOPLEFT")
    page:SetSize(1094, height or 515)
    page.settingsOwner, page.settingsPage = panel, id
    page.pageID, page.contentHeight = id, height or 515
    panel.pages[#panel.pages + 1] = page
    panel.pagesByID[id] = page
    page:Hide()
    return page
end
local function RecommendedBadge(row)
    local badge = CreateFrame("Frame", nil, row)
    badge:SetSize(118, 24)
    badge:SetPoint("RIGHT", row, "RIGHT", -84, 0)
    Rect(badge, 0, 0, 118, 24, 0.02, 0.18, 0.10)
    Border(badge, 0, 0, 118, 24, { 0.15, 0.53, 0.22 })
    Text(badge, L("settings.copy.recommended-baa5"), 6, 0, 106, 24, 11, { 0.36, 0.90, 0.42 }, "CENTER")
    return badge
end
-- Settings rows grow for translated labels; never reduce the shared font size.
RowHeight = function(parent, labels, width, minimum, size)
    local measure=Text(parent,"",0,0,width,1000,size or 16,WHITE)
    measure:SetWordWrap(true)
    local height=minimum
    for _,label in ipairs(labels) do
        measure:SetText(L(label)); height=math.max(height,math.ceil(measure:GetStringHeight())+14)
    end
    measure:Hide(); return height
end
local function Dependency(control, enabled)
    control:SetEnabled(enabled); control:SetAlpha(enabled and 1 or .45)
    if not enabled and control.menu then control.menu:Hide() end
end
local function RoundedChoiceLayers(button)
    local layers={}
    local anchors={"TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT"}
    for layer,path in ipairs({"FlyoutRoundedFill","FlyoutRoundedEdge"}) do
        layers[layer]={}
        for index,anchor in ipairs(anchors) do
            local col=(index-1)%3; local row=math.floor((index-1)/3)
            local uv={0,8/64,56/64,1}
            local texture=button:CreateTexture(nil,layer==1 and "BACKGROUND" or "BORDER")
            texture:SetTexture("Interface\\AddOns\\ForeverFishing\\Media\\"..path)
            texture:SetTexCoord(uv[col+1],uv[col+2],uv[row+1],uv[row+2])
            if col~=1 and row~=1 then texture:SetSize(5,5); texture:SetPoint(anchor,button,anchor,0,0)
            elseif row~=1 then
                texture:SetHeight(5); local side=row==0 and "TOP" or "BOTTOM"
                texture:SetPoint(side.."LEFT",button,side.."LEFT",5,0); texture:SetPoint(side.."RIGHT",button,side.."RIGHT",-5,0)
            elseif col~=1 then
                texture:SetWidth(5); local side=col==0 and "LEFT" or "RIGHT"
                texture:SetPoint("TOP"..side,button,"TOP"..side,0,-5); texture:SetPoint("BOTTOM"..side,button,"BOTTOM"..side,0,5)
            else texture:SetPoint("TOPLEFT",button,"TOPLEFT",5,-5); texture:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-5,5) end
            layers[layer][index]=texture
        end
    end
    return layers
end
local function ChoiceGroup(panel,parent,x,y,w,h,choices,selected,change,help)
    local group=CreateFrame("Frame",nil,parent)
    group:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y); group:SetSize(w,h)
    group.options={}; group.settingsY=y
    group.settingsOwner,group.settingsPage=panel,parent.settingsPage
    local gap=8
    local width=(w-(#choices-1)*gap)/#choices
    for i,choice in ipairs(choices) do
        local button=CreateFrame("Button",nil,group)
        button:SetPoint("TOPLEFT",group,"TOPLEFT",(i-1)*(width+gap),0); button:SetSize(width,h)
        button.roundedLayers=RoundedChoiceLayers(button)
        button.label=Text(button,choice.label,7,1,width-14,h-2,14,WHITE,"CENTER")
        button.label:SetWordWrap(true)
        local function Paint()
            local chosen=selected()==choice.id
            local hover=group:IsEnabled() and button.hover
            local pressed=group:IsEnabled() and button.pressed
            local fill=chosen and {.09,.16,.19,1} or {.045,.085,.11,1}
            local edge=chosen and {.83,.60,.24,1} or {.47,.31,.13,1}
            if pressed then fill={.035,.07,.09,1}
            elseif hover then
                fill=chosen and {.11,.18,.21,1} or {.065,.115,.14,1}
                if not chosen then edge={.59,.39,.16,1} end
            end
            button.selected=chosen; button.paintState=pressed and "pressed" or hover and "hover" or "normal"
            for _,texture in ipairs(button.roundedLayers[1]) do texture:SetVertexColor(unpack(fill)) end
            for _,texture in ipairs(button.roundedLayers[2]) do texture:SetVertexColor(unpack(edge)) end
            -- Inactive hover keeps normal text and a restrained bronze edge;
            -- selection alone owns the gold label/edge.
            button.label:SetTextColor(unpack(chosen and GOLD or WHITE))
        end
        button:SetScript("OnEnter",function() button.hover=true; Paint() end)
        button:SetScript("OnLeave",function() button.hover=nil;button.pressed=nil;Paint() end)
        button:SetScript("OnMouseDown",function() button.pressed=true;Paint() end)
        button:SetScript("OnMouseUp",function() button.pressed=nil;Paint() end)
        button:SetScript("OnHide",function() button.hover=nil;button.pressed=nil;Paint() end)
        button:SetScript("OnClick",function() if group:IsEnabled() then change(choice.id); group:Refresh() end end)
        button.Paint=Paint
        RegisterFocus(group,button,y,h)
        if help then
            button:HookScript("OnEnter",function(owner)
                GameTooltip:SetOwner(owner,"ANCHOR_RIGHT"); TooltipText(L(help)); GameTooltip:Show()
            end)
            button:HookScript("OnLeave",function() GameTooltip:Hide() end)
        end
        group.options[i]={choice=choice,button=button}
    end
    function group:IsEnabled() return self.enabled~=false end
    function group:SetEnabled(enabled)
        self.enabled=enabled==true
        for _,option in ipairs(self.options) do
            option.button:SetEnabled(self.enabled)
            if not self.enabled then option.button.hover=nil;option.button.pressed=nil end
            option.button.Paint()
        end
    end
    function group:Refresh() for _,option in ipairs(self.options) do option.button.Paint() end end
    group:SetEnabled(true); group:Refresh()
    return group
end
local function BuildGeneral(self, panel)
    local page=Page(panel,"general",515); page.compactSettings=true
    Section(page,L("settings.copy.automatic-setup-d8ce"),25,17,1042)
    local rows={
        {{field="autoOpenButton",label="settings.copy.auto-open-6e70",tip="settings.copy.open-the-fishing-bar-when-a-c0e5",click=function(b)
            self.db.autoOpenFishingBar=not self.db.autoOpenFishingBar; b:SetState(self.db.autoOpenFishingBar)
            if self.db.autoOpenFishingBar then self:CheckFishingRodAutoOpen(true) end
        end},{field="fastAutoLootButton",label="settings.copy.fast-auto-loot-c07f",tip="settings.copy.temporarily-enable-auto-loot-while-the-554f",click=function(b)
            self.db.fastAutoLoot=not self.db.fastAutoLoot; self:SyncAutoLoot(); b:SetState(self.db.fastAutoLoot)
        end}},
        {{field="autoEquipGearButton",label="settings.copy.auto-equip-gear-35ec",tip="settings.copy.equip-fishing-gear-when-opening-with-c5af",click=function(b)
            self:SetAutoEquipGear(not self.db.autoEquipGear); b:SetState(self.db.autoEquipGear)
        end},{field="autoRestoreGearButton",label="settings.copy.auto-restore-gear-61d8",tip="settings.copy.restore-your-normal-gear-when-the-b2f2",click=function(b)
            self.db.autoRestoreGear=not self.db.autoRestoreGear; b:SetState(self.db.autoRestoreGear); self:SyncCombatWeaponRestore()
        end}},
        {{field="autoEquipLuresButton",label="settings.copy.auto-equip-lures-3084",tip="settings.copy.include-selected-lure-use-in-the-ad5f",click=function(b)
            self:SetAutoEquipLures(not self.db.autoEquipLures); b:SetState(self.db.autoEquipLures)
        end},{field="hideLureGlowButton",label="settings.copy.hide-lure-glow-when-out-of-5779",tip="settings.copy.hide-the-lure-button-glow-when-7b03",click=function(b)
            self.db.hideLureGlowWhenOutOfLures=not self.db.hideLureGlowWhenOutOfLures; b:SetState(self.db.hideLureGlowWhenOutOfLures); self:RefreshUI()
        end}},
    }
    local y=51
    for _,pair in ipairs(rows) do
        local h=RowHeight(page,{pair[1].label,pair[2].label},451,43)
        for column,entry in ipairs(pair) do
            local b=Toggle(page,column==1 and 25 or 554,y,513,h,entry.label,entry.click,nil,L(entry.tip))
            b.title:SetWordWrap(true); panel[entry.field]=b
        end
        y=y+h+4
    end
    y=y+10
    Section(page,L("settings.keybindings"),25,y,1042); y=y+34
    panel.bindingRows={}
    local function BindingRow(parent,action,prominent)
        local row=CreateFrame("Frame",nil,parent);row:SetSize(1094,48)
        row.settingsOwner,row.settingsPage=panel,"general"
        local entry=self.fishingActions[action]
        local label=prominent and "settings.fishing-key" or entry.label
        local h=RowHeight(row,{label},prominent and 511 or 550,prominent and 72 or 48,prominent and 19 or 16)
        row:SetHeight(h)
        Rect(row,25,0,1042,h,.045,.105,.14,.75)
        if entry.scope=="always" then Rect(row,25,0,3,h,1,.80,.39,.95) end
        local x=40
        if prominent then
            local icon=row:CreateTexture(nil,"ARTWORK");icon:SetTexture(self.castbarIcon)
            icon:SetSize(60,60);icon:SetPoint("LEFT",row,"LEFT",32,0);panel.fishingKeyIcon=icon;x=100
        end
        local title=Text(row,label,x,0,prominent and 511 or 615-(x-40),h,prominent and 19 or 16,(prominent or entry.scope=="always") and GOLD or WHITE)
        title:SetWordWrap(true)
        local controlHeight=prominent and 46 or 36
        local choose=Button(row,prominent and 631 or 673,(h-controlHeight)/2,prominent and 306 or 270,controlHeight,"",function() self:BeginKeyCapture(action) end)
        choose.label:SetWordWrap(true)
        local clear=Button(row,prominent and 950 or 956,(h-controlHeight)/2,prominent and 103 or 97,controlHeight,"binding.clear",function() self:SetFishingActionBinding(action,nil);panel:RefreshBindingControls() end)
        if prominent then
            if not FF:SetDisplayFont(choose.label,FONT,16,"") then choose.label:SetFont("Fonts\\FRIZQT__.TTF",16,"") end
            if not FF:SetDisplayFont(clear.label,FONT,15,"") then clear.label:SetFont("Fonts\\FRIZQT__.TTF",15,"") end
        end
        panel.bindingRows[action]={frame=row,choose=choose,clear=clear,title=title,height=h}
        if entry.scope=="always" then
            row:EnableMouse(true);row:SetScript("OnEnter",function(button)
                GameTooltip:SetOwner(button,"ANCHOR_RIGHT");TooltipText(entry.label)
                GameTooltip:AddLine(L("binding.toggle-help"),.9,.92,.92,true);GameTooltip:Show()
            end);row:SetScript("OnLeave",function() GameTooltip:Hide() end)
        end
        if prominent then panel.keyButton=choose end
        return row,h
    end
    local main,h=BindingRow(page,"fishing",true);main:SetPoint("TOPLEFT",page,"TOPLEFT",0,-y)
    panel.bindingRows.fishing.choose.settingsY=y+(h-panel.keyButton:GetHeight())/2;panel.bindingRows.fishing.clear.settingsY=panel.bindingRows.fishing.choose.settingsY
    y=y+h+4
    local advancedHeight=36
    local advanced=CreateFrame("Button",nil,page)
    advanced.label=Text(advanced,"settings.advanced-bindings",12,1,1002,26,14,WHITE)
    advanced.label:SetWordWrap(false)
    local labelWidth=math.min(1002,math.ceil(advanced.label:GetStringWidth())+2)
    advanced.label:SetWidth(0) -- Natural text width: never abbreviate this label.
    advanced:SetSize(labelWidth+40,advancedHeight)
    advanced:SetPoint("TOP",page,"TOPLEFT",546,-y)
    RegisterFocus(page,advanced,y,advancedHeight)
    local arrow=advanced:CreateTexture(nil,"OVERLAY");arrow:SetSize(10,10);arrow:SetPoint("LEFT",advanced.label,"TOPLEFT",labelWidth+6,-13)
    local underlineWidth=math.min(100,labelWidth)
    local underline=Rect(advanced,12+(labelWidth-underlineWidth)/2,29,underlineWidth,1,unpack(CYAN))
    underline:SetAlpha(.65)
    advanced.underline=underline
    local function PaintDisclosure()
        local active=advanced.hover or advanced.pressed
        advanced.label:SetTextColor(unpack(active and GOLD or WHITE))
        underline:SetAlpha(active and 1 or .65)
    end
    advanced:SetScript("OnClick",function() panel:SetAdvancedBindingsExpanded(not panel.advancedBindingsExpanded) end)
    advanced:SetScript("OnEnter",function()
        advanced.hover=true;PaintDisclosure()
        GameTooltip:SetOwner(advanced,"ANCHOR_RIGHT");TooltipText(L("settings.advanced-bindings"));GameTooltip:Show()
    end)
    advanced:SetScript("OnLeave",function() advanced.hover=nil;advanced.pressed=nil;PaintDisclosure();GameTooltip:Hide() end)
    advanced:SetScript("OnMouseDown",function() advanced.pressed=true;PaintDisclosure() end)
    advanced:SetScript("OnMouseUp",function() advanced.pressed=nil;PaintDisclosure() end)
    advanced:SetScript("OnHide",function() advanced.hover=nil;advanced.pressed=nil;PaintDisclosure() end)
    panel.advancedBindingsButton=advanced;panel.advancedBindingsChevron=arrow;y=y+advancedHeight+4
    local group=CreateFrame("Frame",nil,page);group:SetPoint("TOPLEFT",page,"TOPLEFT",0,-y)
    group.settingsOwner,group.settingsPage=panel,"general";panel.advancedBindingsGroup=group
    local order={"recast","gear","lure","chef-menu","utility-menu","jump","open"}
    for _,action in ipairs(order) do BindingRow(group,action,false) end
    local languageGroup=CreateFrame("Frame",nil,page)
    languageGroup:SetSize(1042,34)
    Section(languageGroup,L("settings.copy.language-a4fe"),0,0,1042)
    local languageHeight=RowHeight(page,{"settings.addon-language"},490,43)
    local languageLabel=Text(page,"settings.addon-language",25,0,490,languageHeight,16,WHITE)
    languageLabel:SetWordWrap(true)
    panel.languageButton=DropDown(panel,page,554,34,513,languageHeight,self:GetLanguageChoices(),
        function() return self:GetResolvedLocale() end,function(choice) self:SetLanguage(choice) end,false)
    panel.languagePreviewHint=Text(page,"language.preview-help",25,0,1042,1,14,MUTED)
    panel.languagePreviewHint:SetWordWrap(true)
    panel.languageReloadHint=Text(page,"language.reload-help",25,0,727,1,14,MUTED)
    panel.languageReloadHint:SetWordWrap(true)
    panel.languageReloadButton=Button(page,772,0,295,38,"language.reload",function() self:ReloadLocalization() end)
    panel.languageReloadHint:Hide();panel.languageReloadButton:Hide()
    panel.languageButton:HookScript("OnEnter",function(button)
        GameTooltip:SetOwner(button,"ANCHOR_RIGHT"); TooltipText(L("settings.copy.language-a4fe"))
        GameTooltip:AddLine(L("language.help"),.9,.92,.92,true); GameTooltip:Show()
    end)
    panel.languageButton:HookScript("OnLeave",function() GameTooltip:Hide() end)
    local guidance=Text(group,"settings.binding-guidance",25,0,1042,1,14,MUTED);guidance:SetWordWrap(true)
    function panel:LayoutGeneralBindings()
        local offset=0
        local jumpNeeded=FF:GetFishingJumpState()
        for _,action in ipairs(order) do
            local row=self.bindingRows[action]
            local shown=action~="jump" or jumpNeeded
            row.frame:SetShown(shown)
            if shown then
                row.frame:ClearAllPoints();row.frame:SetPoint("TOPLEFT",group,"TOPLEFT",0,-offset)
                row.choose.settingsY=y+offset+(row.height-36)/2;row.clear.settingsY=row.choose.settingsY
                offset=offset+row.height+4
            end
        end
        guidance:SetHeight(1000);local gh=math.ceil(guidance:GetStringHeight())+8
        guidance:ClearAllPoints();guidance:SetPoint("TOPLEFT",group,"TOPLEFT",25,-offset);guidance:SetHeight(gh)
        offset=offset+gh;group:SetSize(1094,offset)
        local languageY=y+(self.advancedBindingsExpanded and offset or 0)+12
        languageGroup:ClearAllPoints();languageGroup:SetPoint("TOPLEFT",page,"TOPLEFT",25,-languageY)
        languageLabel:ClearAllPoints();languageLabel:SetPoint("TOPLEFT",page,"TOPLEFT",25,-languageY-34)
        self.languageButton:ClearAllPoints();self.languageButton:SetPoint("TOPLEFT",page,"TOPLEFT",554,-languageY-34)
        self.languageButton.settingsY=languageY+34
        local bottom=languageY+34+languageHeight+14
        local previews=next(FF.previewLocales)~=nil
        self.languagePreviewHint:SetShown(previews)
        if previews then
            self.languagePreviewHint:SetHeight(1000)
            local ph=math.ceil(self.languagePreviewHint:GetStringHeight())+12
            self.languagePreviewHint:ClearAllPoints();self.languagePreviewHint:SetPoint("TOPLEFT",page,"TOPLEFT",25,-bottom)
            self.languagePreviewHint:SetHeight(ph)
            bottom=bottom+ph+14
        end
        local pending=FF:HasPendingLanguageChange()
        self.languageReloadHint:SetShown(pending);self.languageReloadButton:SetShown(pending)
        if pending then
            self.languageReloadHint:SetHeight(1000)
            local rh=math.max(38,math.ceil(self.languageReloadHint:GetStringHeight())+12)
            self.languageReloadHint:ClearAllPoints();self.languageReloadHint:SetPoint("TOPLEFT",page,"TOPLEFT",25,-bottom)
            self.languageReloadHint:SetHeight(rh)
            self.languageReloadButton:ClearAllPoints();self.languageReloadButton:SetPoint("TOPLEFT",page,"TOPLEFT",772,-bottom)
            self.languageReloadButton.settingsY=bottom
            bottom=bottom+rh+14
        end
        page.contentHeight=math.max(515,bottom);page:SetHeight(page.contentHeight)
        if self.activePage=="general" then self.content:SetHeight(page.contentHeight);self:SetPageScroll(page.scrollPosition or 0) end
    end
    function panel:RefreshLanguageControls()
        self.languageButton:Refresh();self:LayoutGeneralBindings()
    end
    function panel:SetAdvancedBindingsExpanded(expanded)
        self.advancedBindingsExpanded=expanded==true;group:SetShown(self.advancedBindingsExpanded)
        FF:SetJournalChevron(arrow,self.advancedBindingsExpanded);arrow:SetVertexColor(unpack(GOLD))
        if self.SetSettingsFocus then self:SetSettingsFocus(nil) end;self:LayoutGeneralBindings()
    end
    function panel:RefreshBindingControls()
        for action,row in pairs(self.bindingRows) do
            local key=FF:GetFishingActionKey(action)
            local displayed=key
            if action=="jump" then local _,effective=FF:GetFishingJumpState();displayed=effective end
            row.choose:SetText(not displayed and L("binding.unassigned") or (FF.GetFishingBindingLabel and FF:GetFishingBindingLabel(displayed)) or displayed)
            if FF:GetResolvedLocale()~="enUS" and FF.FitFishingBindingButton then
                FF:FitFishingBindingButton(row.choose,displayed,L("binding.unassigned"))
            end
            row.clear:SetEnabled(key~=nil)
        end
        self:LayoutGeneralBindings()
    end
    panel:SetAdvancedBindingsExpanded(false)
end
local function BuildFishingView(self,panel)
    local page=Page(panel,"fishing-view",515); page.compactSettings=true
    local y=17
    Section(page,L("information.title"),25,y,1042); y=y+34
    panel.informationRows={}
    local choiceHeight=RowHeight(page,{"ui-hide.never","ui-hide.casts","ui-hide.fishing","progress.off","progress.always","progress.hidden"},326,40,14)
    local h=RowHeight(page,{"information.enabled"},980,43)
    panel.informationRows.enabled=Toggle(page,25,y,1042,h,"information.enabled",function()
        self:SetFishingInformationOption("enabled",not self:GetFishingInformationOptions().enabled)
    end); y=y+h+6
    h=math.max(RowHeight(page,{"information.skill"},451,43),RowHeight(page,{"settings.copy.catch-recap-4e81"},316,43))
    panel.informationRows.skill=Toggle(page,25,y,513,h,"information.skill",function()
        self:SetFishingInformationOption("skill",not self:GetFishingInformationOptions().skill)
    end)
    panel.generalCatchRecapButton=Toggle(page,554,y,513,h,"settings.copy.catch-recap-4e81",function()
        self:SetCatchRecapEnabled(not self.db.catchRecap)
    end,nil,L("settings.copy.briefly-show-items-from-successful-fishing-ea45"))
    panel.generalCatchRecapRecommended=RecommendedBadge(panel.generalCatchRecapButton)
    panel.generalCatchRecapRecommended:ClearAllPoints(); panel.generalCatchRecapRecommended:SetPoint("RIGHT",panel.generalCatchRecapButton,"RIGHT",-12,0)
    panel.generalCatchRecapButton.title:SetWidth(316)
    y=y+h+16; Section(page,L("settings.hide-blizzard-ui"),25,y,1042); y=y+34
    h=choiceHeight
    panel.hideBlizzardUIModeButton=ChoiceGroup(panel,page,25,y,1042,h,{
        {id="never",label=L("ui-hide.never")},{id="casts",label=L("ui-hide.casts")},{id="fishing",label=L("ui-hide.fishing")},
    },function() return self:GetBlizzardUIHideMode() end,function(value) self:SetBlizzardUIHideMode(value) end,"ui-hide.help")
    y=y+h+10
    h=RowHeight(page,{"settings.show-chat","settings.show-minimap"},451,43)
    h=math.max(h,RowHeight(page,{"settings.show-chat"},132,43))
    Rect(page,25,y,513,h,.045,.105,.14,.75)
    panel.chatLabel=Text(page,"settings.show-chat",38,y,132,h,16,WHITE); panel.chatLabel:SetWordWrap(true)
    panel.chatModeButton=DropDown(panel,page,180,y,346,h,{
        {id="hidden",label=L("chat.hidden")},{id="always",label=L("chat.always")},
        {id="whispers",label=L("chat.whispers")},{id="guild",label=L("chat.guild")},
    },function() return self:GetFishingChatMode() end,function(value) self:SetFishingChatMode(value) end,false)
    panel.chatModeButton:HookScript("OnEnter",function(button)
        GameTooltip:SetOwner(button,"ANCHOR_RIGHT"); TooltipText(L("settings.show-chat"))
        GameTooltip:AddLine(L("chat.help"),.9,.92,.92,true); GameTooltip:Show()
    end)
    panel.chatModeButton:HookScript("OnLeave",function() GameTooltip:Hide() end)
    panel.showFishingMinimapButton=Toggle(page,554,y,513,h,"settings.show-minimap",function()
        self:SetFishingMinimapShown(self.db.showFishingMinimap~=true)
    end,nil,L("minimap.help"))
    y=y+h+8
    h=RowHeight(page,{"settings.minimal-cast"},980,43)
    panel.minimalCastButton=Toggle(page,25,y,1042,h,"settings.minimal-cast",function()
        self:SetMinimalFishingCastView(not self.db.minimalFishingCastView)
    end,nil,L("minimal.help"))
    y=y+h+16; Section(page,L("information.progress"),25,y,1042); y=y+34
    h=choiceHeight
    panel.castProgressButton=ChoiceGroup(panel,page,25,y,1042,h,{
        {id="off",label=L("progress.off")},{id="always",label=L("progress.always")},{id="hidden",label=L("progress.hidden")},
    },function() return self:GetFishingInformationOptions().progressMode end,function(value) self:SetFishingCastProgressMode(value) end,"progress.help")
    y=y+h+6
    h=RowHeight(page,{"progress.summary"},1042,24,13)
    panel.castProgressHelp=Text(page,"progress.summary",25,y,1042,h,13,MUTED); panel.castProgressHelp:SetWordWrap(true)
    for _,row in ipairs({panel.informationRows.enabled,panel.informationRows.skill,panel.generalCatchRecapButton,
        panel.minimalCastButton,panel.showFishingMinimapButton}) do row.title:SetWordWrap(true) end
    page.contentHeight=math.max(515,y+h+14); page:SetHeight(page.contentHeight)
    function panel:RefreshInformationControls()
        local options=FF:GetFishingInformationOptions()
        for key,row in pairs(self.informationRows) do
            row:SetState(options[key]); Dependency(row,key=="enabled" or options.enabled)
        end
        self.castProgressButton:Refresh(); Dependency(self.castProgressButton,options.enabled)
        self.castProgressHelp:SetAlpha(options.enabled and 1 or .45)
    end
    function panel:RefreshFishingViewControls()
        self:RefreshInformationControls()
        local hidden=FF:GetBlizzardUIHideMode()~="never"
        self.hideBlizzardUIModeButton:Refresh()
        self.chatModeButton:Refresh(); Dependency(self.chatModeButton,hidden)
        self.chatLabel:SetAlpha(hidden and 1 or .45)
        self.showFishingMinimapButton:SetState(FF.db.showFishingMinimap==true); Dependency(self.showFishingMinimapButton,hidden)
        self.minimalCastButton:SetState(FF.db.minimalFishingCastView==true)
    end
end
local function BuildSounds(self, panel)
    local page = Page(panel, "sounds", 515)
    page.measuredSettings=true
    local stateHeight=RowHeight(page,{"settings.copy.on-1300","settings.copy.off-ca79"},42,46,15)
    local firstHeight=math.max(stateHeight,
        RowHeight(page,{"settings.copy.focus-splash-sound-b3d6"},392,46),
        RowHeight(page,{"settings.copy.enable-alert-sounds-ed2b"},408,46))
    local backgroundY=58+firstHeight+4
    local backgroundHeight=math.max(stateHeight,RowHeight(page,{"settings.copy.sound-in-background-39ab"},392,46))
    local sliderY=math.max(170,backgroundY+backgroundHeight+16)
    Section(page, L("settings.copy.game-sounds-7f6b"), 25, 17, 506)
    Section(page, L("settings.copy.addon-sounds-50bc"), 545, 17, 522)
    panel.soundButton = Toggle(page, 25, 58, 506, firstHeight, L("settings.copy.focus-splash-sound-b3d6"), function(b)
        self.db.soundFocus = not self.db.soundFocus
        self:FocusSplashSound()
        b:SetState(self.db.soundFocus)
        self:RefreshGameSoundSliders()
    end, nil, L("settings.copy.emphasise-the-fishing-splash-while-still-85d1"))
    panel.backgroundSoundButton = Toggle(page, 25, backgroundY, 506, backgroundHeight, L("settings.copy.sound-in-background-39ab"), function()
        self:SetBackgroundSoundEnabled(not self:BackgroundSoundEnabled())
        self:RefreshBackgroundSoundSetting()
    end)
    panel.alertSoundsButton = Toggle(page, 545, 58, 522, firstHeight, L("settings.copy.enable-alert-sounds-ed2b"), function()
        self:SetAlertSoundsEnabled(not self.db.enableAlertSounds)
    end)
    local function CVarSlider(label, cvar, y)
        return Slider(page, 25, y, 506, label, 0, 100, 1, function(v) return string.format(L("settings.copy.d-71fa"), v) end,
            function(v)
                self:SetFocusSplashVolume(cvar, v / 100)
            end, true)
    end
    local function Pair(left,right)
        local height=math.max(left:GetHeight(),right:GetHeight())
        left:SetRowHeight(height); right:SetRowHeight(height)
        sliderY=sliderY+height+1
    end
    panel.masterVolumeRow = CVarSlider(L("settings.copy.master-volume-b041"), "Sound_MasterVolume", sliderY)
    panel.voiceVolumeRow = Slider(page, 545, sliderY, 522, L("settings.copy.voice-alert-volume-2d90"), 0, 100, 10,
        function(v) return string.format(L("settings.copy.d-71fa"), v) end,
        function(v) self:SetVoiceVolume(v); self:RefreshSoundSettings() end)
    Pair(panel.masterVolumeRow,panel.voiceVolumeRow)
    panel.ambientVolumeRow = CVarSlider(L("settings.copy.ambient-sounds-b19b"), "Sound_AmbienceVolume", sliderY)
    panel.reminderRow = Slider(page, 545, sliderY, 522, L("settings.copy.idle-reminder-delay-2e48"), 1, 60, 1,
        function(v) return string.format(L("settings.copy.d-s-515d"), v) end,
        function(v) self:SetRecastReminderDelay(v); self:RefreshSoundSettings() end)
    Pair(panel.ambientVolumeRow,panel.reminderRow)
    panel.musicVolumeRow = CVarSlider(L("settings.copy.music-6eb0"), "Sound_MusicVolume", sliderY)
    panel.repeatRow = Slider(page, 545, sliderY, 522, L("settings.copy.repeat-interval-c48d"), 1, 15, 0.5,
        function(v) return FF:LocalizedText("format.display-spaced-seconds", FF:FormatGeneralDisplay(v)) end,
        function(v) self:SetSoundRepeatInterval(v); self:RefreshSoundSettings() end)
    Pair(panel.musicVolumeRow,panel.repeatRow)
    local sectionY=sliderY
    Rect(page, 538, 25, 1, sectionY-49, 0.21, 0.34, 0.38)
    Section(page, L("settings.copy.event-sounds-5e65"), 25, sectionY, 1042)
    panel.soundOptions = {}
    local definitions = {
        { title = L("settings.copy.recast-reminder-sound-075a"), key = "recastReminderSound", kind = "recast", loop = "recastReminderLoop" },
        { title = L("settings.copy.catch-confirmed-sound-3f30"), key = "catchConfirmedSound", kind = "catch" },
        { title = L("settings.copy.fish-escaped-sound-edef"), key = "fishEscapedSound", kind = "escape" },
    }
    local y=sectionY+40
    local soundLabels={}
    for _,choice in ipairs(self.rangeSoundChoices) do soundLabels[#soundLabels+1]=choice.label end
    local choiceHeight=RowHeight(page,soundLabels,354,38,14)
    local playHeight=RowHeight(page,{"settings.copy.play-436e"},66,35,14)
    local loopHeight=RowHeight(page,{"settings.copy.repeat-b6b7"},73,36)
    for _, spec in ipairs(definitions) do
        local height=math.max(RowHeight(page,{spec.title},306,40,15),choiceHeight+2,playHeight+5,spec.loop and loopHeight+4 or 40)
        Rect(page, 25, y, 1042, height, 0.045, 0.105, 0.14, 0.57)
        Text(page, spec.title, 38, y, 306, height, 15, WHITE):SetWordWrap(true)
        spec.button = DropDown(panel, page, 356, y + 1, 398, height-2, self.rangeSoundChoices,
            function() return self.db[spec.key] end,
            function(id)
                self:SetFishingSound(spec.kind, id)
                self:RefreshSoundSettings()
                self:PreviewFishingSound(spec.kind, id)
            end)
        if spec.loop then
            spec.loopButton = Toggle(page, 766, y + 2, 121, height-4, L("settings.copy.repeat-b6b7"), function()
                self:SetFishingSoundLoop(spec.kind, not self.db[spec.loop])
                self:RefreshSoundSettings()
            end)
            spec.loopButton.state:Hide()
            spec.loopButton.title:SetWidth(73)
        end
        spec.playButton = Button(page, 978, y + 2, 80, height-5, L("settings.copy.play-436e"), function()
            self:PreviewFishingSound(spec.kind, self.db[spec.key])
        end)
        spec.playButton.label:SetWordWrap(true)
        panel.soundOptions[#panel.soundOptions + 1] = spec
        y=y+height+3
    end
    page.contentHeight=math.max(515,y+11); page:SetHeight(page.contentHeight)
end
local function BuildInterface(self, panel)
    local page=Page(panel,"interface",515); page.compactSettings=true
    local y=17
    Section(page,L("settings.buttons-shortcuts"),25,y,1042); y=y+34
    local h=RowHeight(page,{"settings.copy.show-minimap-icon-fa0c","utility.visibility"},405,56)
    local function Card(x,label,icon,callback,help)
        local card=Toggle(page,x,y,513,h,label,callback,nil,help)
        Border(card,0,0,513,h,{.37,.25,.10},1)
        card.title:SetWidth(405);card.title:SetWordWrap(true)
        local art=card:CreateTexture(nil,"ARTWORK");art:SetTexture(icon)
        art:SetSize(32,32);art:SetPoint("RIGHT",card,"RIGHT",-12,0)
        card.icon=art
        return card
    end
    panel.minimapIconButton=Card(25,"settings.copy.show-minimap-icon-fa0c",self.roundIcon,function()
        self:SetMinimapIconShown(self.db.showMinimapIcon==false)
    end,L("settings.copy.show-fishing-s-minimap-icon-or-f972"))
    panel.utilityVisibilityButton=Card(554,"utility.visibility",self.utilitiesIcon,function(button)
        self:SetFishingUtilitiesShown(self.db.showUtilityButton~=true); button:SetState(self.db.showUtilityButton==true)
    end)
    y=y+h+14; Section(page,L("settings.copy.fishing-bar-c149"),25,y,1042); y=y+34
    h=RowHeight(page,{"bar.layout","bar.auto-collapse"},451,43)
    Text(page,"bar.layout",25,y,145,h,16,WHITE):SetWordWrap(true)
    panel.barOrientationButton=DropDown(panel,page,180,y,358,h,{
        {id="horizontal",label=L("bar.horizontal")},{id="vertical",label=L("bar.vertical")},
    },function() return self:GetFishingBarOrientation() end,function(value) self:SetFishingBarOrientation(value) end,false)
    panel.barAutoCollapseButton=Toggle(page,554,y,513,h,"bar.auto-collapse",function(button)
        self:SetFishingBarAutoCollapse(not self:GetFishingBarAutoCollapse()); button:SetState(self:GetFishingBarAutoCollapse())
    end,nil,L("bar.auto-collapse-tooltip")); panel.barAutoCollapseButton.title:SetWordWrap(true)
    y=y+h+4
    panel.iconBarSpacingRow=Slider(page,25,y,513,L("settings.copy.icon-spacing-bcfb"),2,20,1,
        function(v) return string.format(L("settings.copy.d-px-1c85"),v) end,function(v) self:SetIconBarSpacing(v) end)
    local hintHeight=RowHeight(page,{"bar.sizing-hint"},513,41,13)
    Text(page,"bar.sizing-hint",554,y,513,hintHeight,13,MUTED):SetWordWrap(true)
    y=y+math.max(panel.iconBarSpacingRow:GetHeight(),hintHeight)+14
    panel.bobberZoomRow=Slider(page,25,y,513,"Bobber zoom distance",1,15,1,
        function(v) return string.format("%d yd",v) end,function(v) self:SetBobberZoomDistance(v) end)
    y=y+panel.bobberZoomRow:GetHeight()+14
    Section(page,L("settings.copy.flyout-layout-0e5e"),25,y,1042); y=y+34
    panel.flyoutEditScope="all"
    local function Change(key,value) self:SetFishingFlyoutLayout(panel.flyoutEditScope,key,value) end
    panel.flyoutIconSizeRow=Slider(page,25,y,513,L("settings.copy.icon-size-a86c"),32,96,2,
        function(v) return string.format(L("settings.copy.d-px-1c85"),v) end,function(v) Change("size",v) end,true)
    panel.flyoutColumnsRow=Slider(page,554,y,513,L("flyout.icons-per-row"),1,8,1,
        function(v) return tostring(v) end,function(v) Change("columns",v) end,true)
    h=math.max(panel.flyoutIconSizeRow:GetHeight(),panel.flyoutColumnsRow:GetHeight())
    panel.flyoutIconSizeRow:SetRowHeight(h); panel.flyoutColumnsRow:SetRowHeight(h)
    y=y+h+4
    panel.flyoutIconSpacingRow=Slider(page,25,y,513,L("settings.copy.icon-spacing-4d61"),2,20,1,
        function(v) return string.format(L("settings.copy.d-px-1c85"),v) end,function(v) Change("spacing",v) end,true)
    h=math.max(panel.flyoutIconSpacingRow:GetHeight(),RowHeight(page,{"flyout.adjust"},184,41))
    panel.flyoutIconSpacingRow:SetRowHeight(h)
    Text(page,"flyout.adjust",554,y,184,h,16,WHITE):SetWordWrap(true)
    panel.flyoutSelector=DropDown(panel,page,748,y,319,h,{
        {id="all",label=L("flyout.all")},{id="gear",label=L("flyout.gear")},{id="lure",label=L("flyout.lures")},
        {id="chef",label=L("flyout.chef")},{id="utility",label=L("utility.title")},
    },function() return panel.flyoutEditScope end,function(value)
        panel.flyoutEditScope=value; panel:RefreshFlyoutControls()
    end,true)
    panel.flyoutSelector:HookScript("OnEnter",function(button)
        GameTooltip:SetOwner(button,"ANCHOR_RIGHT"); TooltipText(L("flyout.adjust-help")); GameTooltip:Show()
    end)
    panel.flyoutSelector:HookScript("OnLeave",function() GameTooltip:Hide() end)
    y=y+h+14
    Section(page,L("settings.copy.journal-only"),25,y,1042); y=y+34
    panel.journalTextSizeRow=Slider(page,25,y,513,L("settings.copy.journal-text-size-eddf"),85,115,5,
        function(v) return string.format(L("settings.copy.d-71fa"),v) end,function(v) self:SetJournalTextScale(v/100) end)
    h=math.max(panel.journalTextSizeRow:GetHeight(),RowHeight(page,{"settings.copy.journal-faction-59a0"},200,41))
    panel.journalTextSizeRow:SetRowHeight(h)
    Text(page,"settings.copy.journal-faction-59a0",554,y,200,h,16,WHITE):SetWordWrap(true)
    panel.journalFactionButton=DropDown(panel,page,764,y,303,h,{
        {id="Auto",label=L("faction.auto")},{id="Alliance",label=L("faction.alliance")},{id="Horde",label=L("faction.horde")},
    },function() return self.db.journalFaction or "Auto" end,function(value) self:SetJournalFaction(value) end,true)
    page.contentHeight=math.max(515,y+h+14); page:SetHeight(page.contentHeight)
    function panel:RefreshFlyoutControls()
        self.barOrientationButton:Refresh(); self.barAutoCollapseButton:SetState(FF:GetFishingBarAutoCollapse())
        self.flyoutSelector:Refresh()
        local grid,mixed=FF:GetFishingFlyoutEditValues(self.flyoutEditScope)
        self.flyoutIconSizeRow:Refresh(grid.size,mixed.size); self.flyoutColumnsRow:Refresh(grid.columns,mixed.columns)
        self.flyoutIconSpacingRow:Refresh(grid.spacing,mixed.spacing)
    end
end

function FF:BuildCameraBackupSoundControls(panel)
    -- Existing /fish dev layout has room below its diagnostics actions.
    Text(panel, L("settings.copy.cursor-reminder-cd57"), 542, 618, 480, 28, 16, GOLD)
    panel.backupCursorButton = DropDown(panel, panel, 542, 650, 318, 36, self.rangeSoundChoices,
        function() return self.db.rangeSound end,
        function(id) self:SetFishingSound("range", id); self:RefreshCameraBackupSoundControls() end, true)
    panel.backupCursorLoop = Toggle(panel, 870, 650, 150, 36, L("settings.copy.repeat-b6b7"), function()
        self:SetFishingSoundLoop("range", not self.db.rangeSoundLoop)
        self:RefreshCameraBackupSoundControls()
    end)
    panel.backupCursorLoop.state:Hide()
    panel.backupCursorLoop.title:SetWidth(95)
    panel.backupCursorPlay = Button(panel, 542, 696, 145, 30, L("settings.copy.play-436e"), function()
        self:PreviewFishingSound("range", self.db.rangeSound)
    end)
    panel.backupIssueButton = Button(panel, 705, 696, 318, 30, L("settings.copy.report-a-scan-issue-63df"), function()
        GameTooltip:Hide()
        panel:Hide()
        self:BeginScanDiagnostics()
    end)
end
function FF:RefreshCameraBackupSoundControls()
    local p = self.scanDevPanel
    if not p or not p.backupCursorButton then return end
    p.backupCursorButton:Refresh()
    p.backupCursorLoop:SetState(self.db.rangeSoundLoop)
    p.backupIssueButton:SetEnabled(self.db.cameraAssist == true)
end
function FF:RefreshGameSoundSliders()
    local p = self.settingsPanel
    if not p then return end
    local function volume(cvar)
        local v = GetCVar and tonumber(GetCVar(cvar)) or 0
        return math.floor(math.max(0, math.min(1, v or 0)) * 100 + 0.5)
    end
    p.masterVolumeRow:Refresh(volume("Sound_MasterVolume"))
    p.ambientVolumeRow:Refresh(volume("Sound_AmbienceVolume"))
    p.musicVolumeRow:Refresh(volume("Sound_MusicVolume"))
end
function FF:RefreshBackgroundSoundSetting()
    if self.settingsPanel then self.settingsPanel.backgroundSoundButton:SetState(self:BackgroundSoundEnabled()) end
end
function FF:RefreshSoundSettings()
    local p = self.settingsPanel
    if not p then return end
    p.soundButton:SetState(self.db.soundFocus)
    p.alertSoundsButton:SetState(self.db.enableAlertSounds)
    for _, spec in ipairs(p.soundOptions) do
        spec.button:Refresh()
        if spec.loopButton then spec.loopButton:SetState(self.db[spec.loop]) end
    end
    p.voiceVolumeRow:Refresh(self.db.voiceVolume)
    p.reminderRow:Refresh(self.db.recastReminderDelay)
    p.repeatRow:Refresh(self.db.soundRepeatInterval)
    self:RefreshCameraBackupSoundControls()
end
function FF:RefreshCameraScanSetting()
    -- Scan profiles/tuning now live exclusively in the existing developer view.
end
function FF:RefreshFishingModeSetting()
    self:RefreshCameraBackupSoundControls()
end
local PAGE_IDS = { "general", "fishing-view", "interface", "sounds" }
local PAGE_NAMES = { "settings.general", "settings.fishing-view", "settings.interface", "settings.sounds" }
function FF:BuildSettingsPanel()
    if self.settingsPanel then return self.settingsPanel end
    local panel = CreateFrame("Frame", "ForeverFishingSettings", self:EnsureFishingVisibilityRoot(),
        "SecureHandlerStateTemplate")
    panel:SetSize(1148, 768)
    panel:SetPoint("CENTER")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel.settingsOwner, panel.focusables = panel, {}
    Rect(panel, 0, 0, 1148, 768, 0.005, 0.018, 0.026, 0.98)
    Border(panel, 0, 0, 1148, 768, { 0.50, 0.32, 0.08 }, 2)
    Border(panel, 5, 5, 1138, 758, { 0.76, 0.54, 0.16 }, 2)
    Border(panel, 8, 8, 1132, 752, { 0.19, 0.26, 0.27 })
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 27, -15)
    icon:SetSize(65, 65)
    icon:SetTexture(self.roundIcon)
    Text(panel, "settings.title", 107, 14, 665, 47, 30, GOLD)
    Text(panel, L("settings.copy.forever-fishing-fish-0044"), 108, 60, 380, 25, 14, GOLD)
    Button(panel, 949, 32, 129, 40, L("settings.copy.open-journal-f7b5"), function() self:ShowJournal(true) end)
    local close = Button(panel, 1094, 17, 30, 30, "", function() panel:Hide() end)
    local cross = close:CreateTexture(nil, "OVERLAY")
    cross:SetPoint("CENTER", close, "CENTER", 0, 0)
    cross:SetSize(24, 24)
    cross:SetTexture("Interface\\AddOns\\ForeverFishing\\Media\\SettingsCloseX")
    cross:SetVertexColor(unpack(WHITE))
    close:SetScript("OnEnter", function() cross:SetVertexColor(unpack(GOLD)) end)
    close:SetScript("OnLeave", function() cross:SetVertexColor(unpack(WHITE)) end)
    close.icon = cross
    panel.closeButton = close
    Rect(panel, 25, 93, 1098, 2, 0.53, 0.34, 0.08)
    panel.pages = {}
    panel.pagesByID = {}
    panel.tabs = {}
    for i, label in ipairs(PAGE_NAMES) do
        local x = 36 + (i - 1) * 275
        local tab = CreateFrame("Button", nil, panel)
        tab:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -115)
        tab:SetSize(255, 45)
        local caption = Text(tab, label, 0, 0, 255, 40, 16, WHITE, "CENTER")
        caption:SetWordWrap(true)
        local underline = Rect(tab, 0, 41, 255, 3, 0.12, 0.19, 0.22)
        tab.caption, tab.underline = caption, underline
        tab:SetScript("OnClick", function() panel:SelectPage(i) end)
        RegisterFocus(panel, tab, nil, 45)
        panel.tabs[i] = tab
    end
    panel.viewport = CreateFrame("Frame", nil, panel)
    panel.viewport:SetPoint("TOPLEFT", panel, "TOPLEFT", 27, -172)
    panel.viewport:SetSize(1094, 515)
    panel.scroll = CreateFrame("ScrollFrame", nil, panel.viewport)
    panel.scroll:SetPoint("TOPLEFT", panel.viewport, "TOPLEFT")
    panel.scroll:SetSize(1094, 515)
    panel.scroll:EnableMouseWheel(true)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(1094, 515)
    panel.scroll:SetScrollChild(panel.content)
    function panel:SetPageScroll(value)
        local page = self.pagesByID[self.activePage or "general"]
        local maximum = math.max(0, (page and page.contentHeight or 515) - self.scroll:GetHeight())
        value = math.max(0, math.min(maximum, value))
        self.scroll:SetVerticalScroll(value)
        if page then page.scrollPosition = value end
    end
    panel.scroll:SetScript("OnMouseWheel", function(_, delta)
        if panel.openMenu then panel.openMenu:Hide(); panel.openMenu = nil end
        panel:SetPageScroll(panel.scroll:GetVerticalScroll() - delta * 40)
    end)
    Rect(panel.viewport, 0, 0, 1094, 515, 0.02, 0.075, 0.103, 0.92)
    -- The content frame owns its own edge, so its opaque fill cannot cover it.
    Border(panel.viewport, -1, -1, 1096, 517, { 0.58, 0.36, 0.09 }, 2)
    Border(panel.viewport, 2, 2, 1090, 511, { 0.12, 0.22, 0.25 })
    BuildGeneral(self, panel)
    BuildFishingView(self, panel)
    BuildInterface(self, panel)
    BuildSounds(self, panel)
    function panel:SelectPage(id)
        if type(id) == "number" then id = PAGE_IDS[id] end
        if not self.pagesByID[id] then return end
        if self.openMenu then self.openMenu:Hide(); self.openMenu = nil end
        self:SetSettingsFocus(nil)
        self.activePage = id
        for i, page in ipairs(self.pages) do
            local selected = page.pageID == id
            page:SetShown(selected)
            self.tabs[i].caption:SetTextColor(unpack(selected and GOLD or WHITE))
            Color(self.tabs[i].underline, unpack(selected and GOLD or { .12, .19, .22 }))
        end
        local page = self.pagesByID[id]
        self.content:SetHeight(page.contentHeight)
        self:SetPageScroll(page.scrollPosition or 0)
        if id == "general" then self:RefreshBindingControls() end
        if FF.settingsKeyboardFocus then
            for index, pageID in ipairs(PAGE_IDS) do
                if pageID == id then self:SetSettingsFocus(self.tabs[index]); break end
            end
        end
        if id ~= "sounds" then FF:StopFishingSoundPreview() end
    end
    Rect(panel, 26, 700, 1096, 1, 0.53, 0.34, 0.08)
    Text(panel, L("settings.copy.changes-are-saved-automatically-a99d"), 32, 708, 470, 31, 13, MUTED)
    Button(panel, 898, 712, 224, 40, L("settings.copy.reset-all-settings-ef4d"), function()
        self:ShowSettingsResetConfirmation()
    end)
    panel:SetScript("OnHide", function()
        panel:SetSettingsFocus(nil)
        FF.settingsKeyboardFocus = nil
        if FF.ApplyBindings then FF:ApplyBindings() end
        if panel.openMenu then
            if InCombatLockdown and InCombatLockdown() then
                self.pendingSettingsMenuClose = panel.openMenu
            else
                panel.openMenu:Hide()
            end
            panel.openMenu = nil
        end
        self:StopFishingSoundPreview()
    end)
    InstallSettingsFocus(panel)
    panel:SelectPage("general")
    panel:Hide()
    self:PrepareFloatingWindow(panel, "settings", panel)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "ForeverFishingSettings" end
    self:RegisterCombatCloseWindow("settings", panel)
    self.settingsPanel = panel
    return panel
end
function FF:ShowModernSettings()
    if InCombatLockdown and InCombatLockdown() then return end
    local p = self.settingsPanel or self:BuildSettingsPanel()
    self:RefreshSoundSettings()
    self:RefreshBackgroundSoundSetting()
    self:RefreshGameSoundSliders()
    self:RefreshFishingModeSetting()
    p.autoOpenButton:SetState(self.db.autoOpenFishingBar)
    p.autoRestoreGearButton:SetState(self.db.autoRestoreGear)
    p.journalFactionButton:Refresh()
    p.languageButton:Refresh()
    p.minimapIconButton:SetState(self.db.showMinimapIcon ~= false)
    p.utilityVisibilityButton:SetState(self.db.showUtilityButton == true)
    p:RefreshFishingViewControls()
    p.hideLureGlowButton:SetState(self.db.hideLureGlowWhenOutOfLures)
    p.autoEquipGearButton:SetState(self.db.autoEquipGear)
    p.autoEquipLuresButton:SetState(self.db.autoEquipLures)
    p.fastAutoLootButton:SetState(self.db.fastAutoLoot)
    p.hideBlizzardUIModeButton:Refresh()
    p.journalTextSizeRow:Refresh(self:GetJournalTextScale() * 100)
    p.iconBarSpacingRow:Refresh(self:GetIconBarSpacing())
    if p.bobberZoomRow then p.bobberZoomRow:Refresh(self:GetBobberZoomDistance()) end
    p:RefreshFlyoutControls()
    self:RefreshCatchRecapSetting()
    p:RefreshBindingControls()
    self:ShowFloatingWindow(p)
end
