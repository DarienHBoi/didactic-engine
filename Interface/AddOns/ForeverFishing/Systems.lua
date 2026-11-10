-- Forever Fishing
-- Copyright © 2026 Hamish336. All Rights Reserved.
-- Applies to original Forever Fishing code and assets only.
-- Blizzard-owned assets and trademarks remain property of Blizzard Entertainment.
-- Unauthorized redistribution or modification is prohibited.
local FF = _G.ForeverFishing

local DEFAULT_GEAR_ICON = "Interface\\Icons\\INV_Fishingpole_02"
local DEFAULT_LURE_ICON = "Interface\\Icons\\INV_Misc_Fish_14"

local LURE_MACRO_NAME = "FF Apply Lure"
local function NormalizeMacroBody(body)
    if type(body) ~= "string" then return nil end
    body = body:gsub("\r\n", "\n"):gsub("\r", "\n")
    return body:match("^%s*(.-)%s*$")
end

local function IsManagedLureMacro(body)
    body = NormalizeMacroBody(body)
    return body and body:match("^/use %d+ %d+\n/use 16$") ~= nil
end

local KNOWN_LURES = {
    [6529] = 25,   -- Shiny Bauble
    [6530] = 50,   -- Nightcrawlers
    [6532] = 75,   -- Bright Baubles
    [6533] = 100,  -- Aquadynamic Fish Attractor
    [6811] = 50,   -- Aquadynamic Fish Lens
    [7307] = 75,   -- Flesh Eating Worm
}

function FF:IsKnownFishingLure(id)
    return KNOWN_LURES[id] ~= nil
end

function FF:GetRecognizedLureForSpell(spellID)
    if type(spellID) ~= "number" then return end
    -- Ownership/selection is not use. Resolve a native player cast against
    -- recognised item-use spells; an ambiguous spell cannot identify a lure.
    local match
    local candidates = {}
    for id in pairs(KNOWN_LURES) do candidates[id] = true end
    for _, entry in ipairs(self.availableLures or {}) do
        if entry.recognized then candidates[entry.id] = true end
    end
    local query = GetItemSpell or (C_Item and C_Item.GetItemSpell)
    if not query then return end
    for id in pairs(candidates) do
        local ok, _, useSpell = pcall(query, id)
        if ok and useSpell == spellID then
            if match then return end
            match = id
        end
    end
    return match
end

local EQUIP_SLOTS = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4,
    INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7,
    INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
    INVTYPE_TRINKET = 13, INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16,
    INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16, INVTYPE_SHIELD = 17,
    INVTYPE_HOLDABLE = 17, INVTYPE_WEAPONOFFHAND = 17, INVTYPE_RANGED = 18,
    INVTYPE_RANGEDRIGHT = 18, INVTYPE_THROWN = 18, INVTYPE_RELIC = 18,
    INVTYPE_TABARD = 19,
}

local SLOT_LABEL_KEYS = {
    [1] = "gear.slot.head",
    [2] = "gear.slot.neck",
    [3] = "gear.slot.shoulders",
    [4] = "gear.slot.shirt",
    [5] = "gear.slot.chest",
    [6] = "gear.slot.waist",
    [7] = "gear.slot.legs",
    [8] = "gear.slot.feet",
    [9] = "gear.slot.wrists",
    [10] = "gear.slot.hands",
    [11] = "gear.slot.finger-one",
    [12] = "gear.slot.finger-two",
    [13] = "gear.slot.trinket-one",
    [14] = "gear.slot.trinket-two",
    [15] = "gear.slot.back",
    [16] = "gear.slot.main-hand",
    [17] = "gear.slot.off-hand",
    [18] = "gear.slot.ranged",
    [19] = "gear.slot.tabard",
}
local function GearSlotLabel(slot, title)
    local key=SLOT_LABEL_KEYS[slot]
    return key and FF:LocalizedText(key) or FF:LocalizedText(title and "gear.slot-fallback-title" or "gear.slot-fallback",slot)
end

local function ItemInfo(id)
    if not id then return nil end
    local name, link, quality, _, _, _, _, _, equipLoc, icon
    if GetItemInfo then name, link, quality, _, _, _, _, _, equipLoc, icon = GetItemInfo(id) end
    if not icon then
        if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id)
        elseif GetItemIcon then icon = GetItemIcon(id) end
    end
    if not equipLoc then
        local getter = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
        if getter then
            local ok, _, _, _, location, instantIcon = pcall(getter, id)
            if ok then equipLoc, icon = location, icon or instantIcon end
        end
    end
    return name or ("Item " .. id), link or ("item:" .. id), quality or 1, equipLoc, icon
end

local function FriendlyItemName(id, link, fallback)
    local name = id and GetItemInfo and GetItemInfo(id)
    if name then return name end
    local linkedName = type(link) == "string" and link:match("%[([^%]]+)%]")
    if linkedName and linkedName ~= "" then return linkedName end
    if type(fallback) == "string" and not fallback:match("^Item %d+$") then return fallback end
    return "Fishing item"
end

local function ContainerSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function ContainerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount or 1, info.hyperlink, info.iconFileID, info.isLocked end
    elseif GetContainerItemInfo then
        local icon, count, locked, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
        return itemID, count or 1, link, icon, locked
    end
end

-- Compare persistent item variants, not link colour/name/player-level fields.
-- Old records containing only an ID remain valid; known zero enchant matters.
local function SameGearItem(entry, id, link)
    if not entry or entry.id ~= id then return false end
    local saved = type(entry.link) == "string" and entry.link:match("item:([%d:%-]+)")
    if not saved or not saved:find(":", 1, true) then return true end
    local worn = type(link) == "string" and link:match("item:([%d:%-]+)")
    if not worn then return false end
    local a, b = {}, {}
    for value in (saved .. ":"):gmatch("([^:]*):") do a[#a + 1] = tonumber(value) or 0 end
    for value in (worn .. ":"):gmatch("([^:]*):") do b[#b + 1] = tonumber(value) or 0 end
    -- Permanent enchant, gems and random suffix; unique/link-level fields vary.
    for field = 2, math.min(#a, 7) do
        if a[field] ~= (b[field] or 0) then return false end
    end
    return true
end

local function GearItemEquipped(entry, slot)
    if not GetInventoryItemID then return false end
    local id = GetInventoryItemID("player", slot)
    if entry.id == 0 then return not id end
    return SameGearItem(entry, id, GetInventoryItemLink and GetInventoryItemLink("player", slot))
end

local function TooltipDataText(info)
    if not info or not info.lines then return "" end
    local parts = {}
    for _, line in ipairs(info.lines) do
        if line.leftText then parts[#parts + 1] = line.leftText end
        if line.rightText then parts[#parts + 1] = line.rightText end
    end
    return table.concat(parts, " "):lower()
end

local function TooltipText(bag, slot)
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local ok, info = pcall(C_TooltipInfo.GetBagItem, bag, slot)
        if ok and info then return TooltipDataText(info) end
    end
    if CreateFrame then
        if not FF.lureScanTooltip then
            FF.lureScanTooltip = CreateFrame("GameTooltip", "ForeverFishingLureScanTooltip", UIParent, "GameTooltipTemplate")
            FF.lureScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        end
        local tooltip = FF.lureScanTooltip
        tooltip:ClearLines()
        local ok = pcall(tooltip.SetBagItem, tooltip, bag, slot)
        if ok then
            local parts = {}
            for index = 1, tooltip:NumLines() do
                local left = _G["ForeverFishingLureScanTooltipTextLeft" .. index]
                local right = _G["ForeverFishingLureScanTooltipTextRight" .. index]
                if left and left:GetText() then parts[#parts + 1] = left:GetText() end
                if right and right:GetText() then parts[#parts + 1] = right:GetText() end
            end
            return table.concat(parts, " "):lower()
        end
    end
    return ""
end

local function InventoryTooltipText(slot)
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local ok, info = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
        if ok and info then return TooltipDataText(info) end
    end
    if CreateFrame then
        if not FF.gearScanTooltip then
            FF.gearScanTooltip = CreateFrame("GameTooltip", "ForeverFishingGearScanTooltip", UIParent, "GameTooltipTemplate")
            FF.gearScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        end
        local tooltip = FF.gearScanTooltip
        tooltip:ClearLines()
        local ok = pcall(tooltip.SetInventoryItem, tooltip, "player", slot)
        if ok then
            local parts = {}
            for index = 1, tooltip:NumLines() do
                local left = _G["ForeverFishingGearScanTooltipTextLeft" .. index]
                local right = _G["ForeverFishingGearScanTooltipTextRight" .. index]
                if left and left:GetText() then parts[#parts + 1] = left:GetText() end
                if right and right:GetText() then parts[#parts + 1] = right:GetText() end
            end
            return table.concat(parts, " "):lower()
        end
    end
    return ""
end

local function InstantInfo(id)
    local getter = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not getter then return nil end
    local ok, _, _, _, equipLoc, icon, classID, subclassID = pcall(getter, id)
    if not ok then return nil end
    return equipLoc, icon, classID, subclassID
end

-- One synchronous discovery pass. Positions may hint the resulting equip
-- operation, but item identity and lock state must be read again before use.
local function BagScan()
    local entries = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, ContainerSlots(bag) do
            local id, count, link, icon = ContainerItem(bag, slot)
            if id then
                entries[#entries + 1] = { id = id, count = count, link = link,
                    icon = icon, bag = bag, slot = slot }
            end
        end
    end
    return entries
end

local function BagScanText(entry)
    if entry.text == nil then entry.text = TooltipText(entry.bag, entry.slot) end
    return entry.text
end

local function BagScanInstant(entry)
    if not entry.instantRead then
        entry.equipLoc, entry.instantIcon, entry.classID, entry.subclassID = InstantInfo(entry.id)
        entry.instantRead = true
    end
    return entry
end

local function IsLure(id, bag, slot, entry)
    if KNOWN_LURES[id] then return true end
    local text = entry and BagScanText(entry) or TooltipText(bag, slot)
    if text == "" then return false end
    local fishingBonus = text:find("fishing skill", 1, true) or text:find("increases fishing", 1, true)
    local lureUse = text:find("fishing lure", 1, true) or text:find("fishing pole", 1, true) or text:find("bait", 1, true)
    return fishingBonus and lureUse or false
end

local function CreatePicker(name, kind)
    local panel = FF:CreateFishingQuickTray(name, nil, kind)
    panel.rows = {}
    return panel
end

function FF:PositionFishingPicker(panel, owner)
    return self:PositionFishingFlyout(panel, owner)
end

local function PickerRow(panel, index)
    local row = panel.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, panel.content)
    FF:StyleFishingFlyoutIcon(row, panel)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    FF:StyleFishingFlyoutAddButton(row)
    function row:SetIcon(icon, selected)
        self.icon:SetTexture(icon)
        self.icon:SetShown(icon ~= nil)
        self.plusHorizontal:SetShown(icon == nil)
        self.plusVertical:SetShown(icon == nil)
        self.flyoutEdge:SetVertexColor(selected and 1 or 0.72,
            selected and 0.77 or 0.52, selected and 0.39 or 0.25,
            selected and 1 or 0.88)
    end
    local function ShowItemTooltip(button)
        local id = button.itemID
        if not id then return false end
        local function HasTooltip()
            return GameTooltip:NumLines() > 0
        end
        local bag, slot = button.itemBag, button.itemBagSlot
        if bag and slot and ContainerItem(bag, slot) == id then
            GameTooltip:ClearLines()
            if pcall(GameTooltip.SetBagItem, GameTooltip, bag, slot) and HasTooltip() then return true end
        end
        local equipSlot = button.itemEquipSlot
        if equipSlot and GetInventoryItemID and GetInventoryItemID("player", equipSlot) == id then
            GameTooltip:ClearLines()
            if pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", equipSlot) and HasTooltip() then return true end
        end
        for bagIndex = 0, NUM_BAG_SLOTS or 4 do
            for bagSlot = 1, ContainerSlots(bagIndex) do
                if ContainerItem(bagIndex, bagSlot) == id then
                    GameTooltip:ClearLines()
                    if pcall(GameTooltip.SetBagItem, GameTooltip, bagIndex, bagSlot) and HasTooltip() then return true end
                end
            end
        end
        GameTooltip:ClearLines()
        if pcall(GameTooltip.SetHyperlink, GameTooltip, button.itemLink or ("item:" .. id)) and HasTooltip() then return true end
        return false
    end
    row:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        if not ShowItemTooltip(button) then
            GameTooltip:ClearLines()
            GameTooltip:SetText(button.tooltipTitle or "")
            if button.tooltipLine then GameTooltip:AddLine(button.tooltipLine, 0.84, 0.81, 0.72, true) end
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.rows[index] = row
    return row
end

function FF:InitializeFishingSystems()
    if type(self.db.gearItems) ~= "table" then self.db.gearItems = {} end
    if type(self.db.gearIgnored) ~= "table" then self.db.gearIgnored = {} end
    if type(self.db.normalWeaponsBySpec) ~= "table" then self.db.normalWeaponsBySpec = {} end
    if type(self.db.normalGearSetBySpec) ~= "table" then self.db.normalGearSetBySpec = {} end
    if type(self.db.normalWeaponsBySet) ~= "table" then self.db.normalWeaponsBySet = {} end
    self:CancelGearOperation()
    self:BindCharacterFishingGear()
    self:RecoverCharacterGearSnapshot()
    self.gearSwapBlocked = nil
    self.gearWorldInterrupted = nil
    self:RecoverCombatWeaponRestore()
    self.db.gear = nil
    self.db.gearMode = nil
    self.db.gearReturnSet = nil
    self.db.gearDiscoveryVersion = nil
    self.db.lureMacroOwned = nil
    if self.db.lureManual == nil then self.db.lureManual = self.db.lure ~= nil end
    self.availableLures = {}
    self:ScanFishingInventory()
end

local function LureBonus(id, bag, slot, entry)
    if KNOWN_LURES[id] then return KNOWN_LURES[id] end
    local text = entry and BagScanText(entry) or TooltipText(bag, slot)
    return tonumber(text:match("%+(%d+)%s+fishing"))
        or tonumber(text:match("fishing skill[^%d]+(%d+)"))
        or tonumber(text:match("increases fishing[^%d]+(%d+)"))
        or 0
end

function FF:ScanLures(scan)
    local found = {}
    for _, item in ipairs(scan or BagScan()) do
        local id, count, link, icon, bag, slot = item.id, item.count, item.link, item.icon, item.bag, item.slot
        if IsLure(id, bag, slot, item) or (self.db.lureManual and id == self.db.lure) then
            local entry = found[id]
            if not entry then
                local name, itemLink, quality, _, itemIcon = ItemInfo(id)
                entry = { id = id, name = name, link = link or itemLink, quality = quality, icon = icon or itemIcon, count = 0, bag = bag, slot = slot, bonus = LureBonus(id, bag, slot, item), recognized = not not IsLure(id, bag, slot, item) }
                found[id] = entry
            end
            entry.count = entry.count + (count or 1)
        end
    end
    self.availableLures = {}
    for _, entry in pairs(found) do self.availableLures[#self.availableLures + 1] = entry end
    table.sort(self.availableLures, function(a, b)
        if a.bonus ~= b.bonus then return a.bonus > b.bonus end
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.name < b.name
    end)
    if not self.db.lureManual then self.db.lure = self.availableLures[1] and self.availableLures[1].id or nil end
    self:SyncLureButton()
    if self.lurePicker and self.lurePicker:IsShown() then self:RefreshLurePicker() end
end

function FF:ValidateSelectedLureSlot()
    if InCombatLockdown and InCombatLockdown() then return false end
    for _, entry in ipairs(self.availableLures or {}) do
        if entry.id == self.db.lure then
            local id, count = ContainerItem(entry.bag, entry.slot)
            if id ~= entry.id or not count or count <= 0 then
                self:ScanLures()
                return true
            end
            return false
        end
    end
    return false
end

function FF:SetLure(id)
    if InCombatLockdown and InCombatLockdown() then self:Print(FF:LocalizedText("lure.choose-combat")); return end
    id = tonumber(id)
    if not id or id <= 0 then self:Print(FF:LocalizedText("lure.choose-help")); return end
    self.db.lure = id
    self.db.lureManual = true
    self:ScanLures()
    self:RefreshUI()
    self:Print(FF:LocalizedText("lure.selected-message",ItemInfo(id) or ("item " .. id)))
end

function FF:EnsureLureMacro(entry)
    if not entry or not GetMacroIndexByName or not GetMacroBody then return nil end
    -- Bag/slot syntax works for localized and uncached item names. Refresh it
    -- when bags move; the second /use targets the equipped main-hand pole.
    local body = "/use " .. entry.bag .. " " .. entry.slot .. "\n/use 16"
    local freeName, blocked = nil, false
    for suffix = 1, 9 do
        local name = suffix == 1 and LURE_MACRO_NAME or (LURE_MACRO_NAME .. " " .. suffix)
        local index = GetMacroIndexByName(name)
        if index and index > 0 then
            local existing = GetMacroBody(index)
            if existing == nil then
                blocked = true
            elseif IsManagedLureMacro(existing) then
                if NormalizeMacroBody(existing) == body then return index end
                if EditMacro then
                    local ok, edited = pcall(EditMacro, index, nil, nil, body)
                    if ok then
                        local updatedIndex = type(edited) == "number" and edited > 0 and edited or index
                        if NormalizeMacroBody(GetMacroBody(updatedIndex)) == body then return updatedIndex, true end
                    end
                end
                blocked = true
            end
        elseif not freeName then
            freeName = name
        end
    end
    if blocked then
        self.lureMacroError = FF:LocalizedText("lure.macro-temporary")
        return nil
    end
    if freeName and CreateMacro then
        local ok, created = pcall(CreateMacro, freeName, 134400, body, true)
        if ok and type(created) == "number" and created > 0 then return created, true end
    end
    self.lureMacroError = freeName and FF:LocalizedText("lure.macro-slots") or FF:LocalizedText("lure.macro-names")
    return nil
end

function FF:SyncLureButton()
    local button = self.lureButton
    if not button or (InCombatLockdown and InCombatLockdown()) then return end
    local selected
    for _, entry in ipairs(self.availableLures or {}) do
        if entry.id == self.db.lure then selected = entry; break end
    end
    local previousError = self.lureMacroError
    self.lureMacroError = nil
    local index, macroChanged
    if selected then index, macroChanged = self:EnsureLureMacro(selected) end
    -- A new lure macro can move the cast macro to another numeric slot.
    -- Refresh it here, before the next fishing-key press, even if the macro
    -- update event is delivered later.
    if macroChanged then self:RefreshCastMacro() end
    if self.lureMacroError and self.lureMacroError ~= previousError then self:Print(self.lureMacroError) end
    button:SetAttribute("type1", index and "macro" or nil)
    button:SetAttribute("macro", index)
    button:SetAttribute("macro1", index)
    button:SetAttribute("macrotext", nil)
    button:SetAttribute("macrotext1", nil)
end

function FF:ShowLurePicker()
    if InCombatLockdown and InCombatLockdown() then
        self:Print(FF:LocalizedText("lure.choose-combat"))
        return
    end
    if self.IsCameraSearchPending and self:IsCameraSearchPending() then return end
    if self.utilityPicker then self.utilityPicker:Hide() end
    self:EnsureFishingBarExpanded()
    if self.lurePicker and self.lurePicker:IsShown() then
        self.lurePicker:Hide()
        return
    end
    if self.CloseFishingQuickTray then self:CloseFishingQuickTray() end
    self:ScanLures()
    if not self.lurePicker then
        self.lurePicker = CreatePicker("ForeverFishingLurePicker", "lure")
        self:BindFishingFlyoutOwner(self.lurePicker)
    end
    self:RefreshLurePicker()
    if self.gearPicker then self.gearPicker:Hide() end
    self:RefreshFishingLayer()
    self:PositionFishingPicker(self.lurePicker, self.lureButton)
    self.lurePicker:Show()
end

function FF:RefreshLurePicker()
    if InCombatLockdown and InCombatLockdown() then return end
    local panel = self.lurePicker
    if not panel then return end
    if not panel.flyoutGeometryLocked then
        for _, row in ipairs(panel.rows) do row:Hide() end
    end
    local entries = {}
    local bestLure = self.availableLures and self.availableLures[1]
    entries[#entries + 1] = {
        auto = true, name = FF:LocalizedText("lure.best"), icon = self.lureIcon or DEFAULT_LURE_ICON,
        bestName = bestLure and FriendlyItemName(bestLure.id, bestLure.link, bestLure.name)
            or FF:LocalizedText("lure.next-found"),
    }
    for _, entry in ipairs(self.availableLures or {}) do entries[#entries + 1] = entry end
    entries[#entries + 1] = { add = true, name = FF:LocalizedText("lure.add") }
    entries = self:ResolveFishingFlyoutEntries(panel,entries)
    for index, entry in ipairs(entries) do
        local pickerEntry = entry
        local lureID = entry.id
        local row = PickerRow(panel, index)
        if not panel.flyoutGeometryLocked then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel.content, "TOPLEFT",
                ((index - 1) % panel.flyoutColumns) * panel.flyoutStep,
                -math.floor((index - 1) / panel.flyoutColumns) * panel.flyoutStep)
        end
        local autoSelected = entry.auto and not self.db.lureManual
        local selected = autoSelected or (entry.id and self.db.lureManual and entry.id == self.db.lure)
        row:SetIcon(entry.icon, selected)
        self:SetFishingFlyoutSelectionGlow(row, selected)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.itemID = entry.id
        row.itemLink = entry.link
        row.itemBag = entry.bag
        row.itemBagSlot = entry.slot
        row.itemEquipSlot = nil
        row.tooltipTitle = entry.id and FriendlyItemName(entry.id, entry.link, entry.name) or entry.name
        row.tooltipLine = entry.add and FF:LocalizedText("lure.drop")
            or (entry.auto and (FF:LocalizedText("lure.uses",entry.bestName))
            or (FF:LocalizedText("lure.bonus-bags",entry.bonus or 0,entry.count or 0)))
        if entry.add then
            local function AddDroppedLure()
                local kind, id = GetCursorInfo()
                if kind == "item" and tonumber(id) then
                    self:SetLure(tonumber(id))
                    ClearCursor()
                    self:FinishFishingFlyoutSelection(panel)
                end
            end
            row:SetScript("OnClick", function(_, button)
                if button == "LeftButton" then AddDroppedLure() end
            end)
            row:SetScript("OnReceiveDrag", AddDroppedLure)
        else
            row:SetScript("OnReceiveDrag", nil)
            row:SetScript("OnClick", function()
                if pickerEntry.auto then
                    self.db.lureManual = false
                    self:ScanLures()
                    self:RefreshUI()
                    self:Print(FF:LocalizedText("lure.best-selected"))
                else
                    self:SetLure(lureID)
                end
                self:FinishFishingFlyoutSelection(panel)
            end)
        end
        row:SetEnabled(not entry.flyoutUnavailable)
        row:SetAlpha(entry.flyoutUnavailable and .35 or 1)
        row:Show()
    end
    panel.flyoutFixedButton = panel.rows[#entries]
    if not panel.flyoutGeometryLocked then panel:SizeForRows(#entries) end
    if panel:IsShown() then self:PositionFishingPicker(panel, self.lureButton) end
end

local function CaptureSlots(slots)
    local snapshot = {}
    for slot in pairs(slots) do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        snapshot[slot] = {
            id = id or 0,
            link = id and GetInventoryItemLink and GetInventoryItemLink("player", slot) or nil,
        }
    end
    return snapshot
end

function FF:GearCharacterKey()
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) == "string" and guid ~= "" then return guid end
    local name = UnitName and UnitName("player") or "player"
    local realm = GetRealmName and GetRealmName() or "realm"
    return tostring(realm) .. ":" .. tostring(name)
end

local function ValidGearBonus(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) == "number" and value == value and value >= 0 and value < math.huge then return value end
end

local function CopyFishingChoices(items)
    local copy = {}
    for slot, entry in pairs(items or {}) do
        if type(entry) == "table" then
            copy[slot] = {}
            for key, value in pairs(entry) do copy[slot][key] = value end
        else copy[slot] = entry end
    end
    return copy
end

function FF:BindCharacterFishingGear()
    local db, owner = self.db, self:GearCharacterKey()
    if type(db.fishingGearByCharacter) ~= "table" then db.fishingGearByCharacter = {} end
    local profiles = db.fishingGearByCharacter
    -- Public saves had one unscoped selection. Retain it without guessing
    -- that another character's missing rod belongs to the first login.
    if not db.fishingGearOwner and not db.legacyFishingGear
        and (next(db.gearItems or {}) or next(db.gearIgnored or {})) then
        db.legacyFishingGear = { items = db.gearItems, ignored = db.gearIgnored,
            owner = db.gearSwapOwner }
    end
    local previous = db.fishingGearOwner
    if type(previous) == "string" and not profiles[previous] then
        profiles[previous] = { items = db.gearItems, ignored = db.gearIgnored }
    end
    local legacy = db.legacyFishingGear
    if type(legacy) == "table" and type(legacy.owner) == "string" and not profiles[legacy.owner] then
        local ignored = {}
        for id, value in pairs(legacy.ignored or {}) do ignored[id] = value end
        profiles[legacy.owner] = { items = CopyFishingChoices(legacy.items), ignored = ignored }
    end
    if type(profiles[owner]) ~= "table" then profiles[owner] = { items = {}, ignored = {} } end
    local profile = profiles[owner]
    if type(profile.items) ~= "table" then profile.items = {} end
    if type(profile.ignored) ~= "table" then profile.ignored = {} end
    if type(profile.legacyImported) ~= "table" then profile.legacyImported = {} end
    -- Existing callers retain their active aliases; the character profile is
    -- canonical across serialization/reload (which may duplicate alias tables).
    db.gearItems, db.gearIgnored, db.fishingGearOwner = profile.items, profile.ignored, owner
    self.fishingGearProfile, self.fishingGearProfileDB = profile, db
    self.availableFishingGear, self.availableGearOwned = nil, nil
    self.availableGearOwner, self.availableGearSelection, self.availableGearSet = nil, nil, nil
    self.availableGearMissing, self.availableGearHasRod = nil, nil
    self.fishingGearNoticeState = nil
    self.combatWeaponPlanDirty = true
end

function FF:AdoptOwnedLegacyFishingGear(owned)
    local legacy, profile = self.db.legacyFishingGear, self.fishingGearProfile
    if type(legacy) ~= "table" or legacy.owner or self.fishingGearProfileDB ~= self.db or not profile then return end
    -- Unowned old choices stay recoverable. Later inventory scans may adopt a
    -- returned original, but explicit character choices/removals always win.
    for slot, entry in pairs(legacy.items or {}) do
        local current = self.db.gearItems[slot]
        if type(entry) == "table" and not profile.legacyImported[slot]
            and not self.db.gearIgnored[entry.id] and (not self.db.gearSwapActive or current)
            and (not current or current.detected == true) then
            for _, item in ipairs(owned[entry.id] or {}) do
                if (not item.slot or item.slot == slot) and SameGearItem(entry, entry.id, item.link) then
                    local oldBonus = ValidGearBonus(entry.baseFishingBonus)
                    local currentBonus = current and ValidGearBonus(current.baseFishingBonus)
                    -- Compatibility must not downgrade an already proven
                    -- automatic choice when tooltip data is temporarily absent.
                    if not current or entry.detected ~= true
                        or (oldBonus and currentBonus and oldBonus > currentBonus) then
                        self.db.gearItems[slot] = CopyFishingChoices({ [slot] = entry })[slot]
                    end
                    profile.legacyImported[slot] = true
                    break
                end
            end
        end
    end
    -- Unowned legacy removal IDs cannot identify a character; they remain in
    -- the retained legacy record instead of excluding another character's rod.
end

local function ReadSpecGroup(getter)
    if type(getter) == "function" then
        local ok, group = pcall(getter)
        if ok and type(group) == "number" and group > 0 then return group end
    end
end

local function CurrentGearSpecKey(self)
    local group = ReadSpecGroup(C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup)
        or ReadSpecGroup(GetActiveSpecGroup)
        or ReadSpecGroup(GetActiveTalentGroup)
        or 1
    return self:GearCharacterKey() .. ":" .. tostring(group)
end

local function IsFishingWeapon(self, slot, id)
    if not id or id == 0 then return false end
    local selected = self.db.gearItems[slot]
    if selected and selected.id == id then return true end
    local _, _, classID, subclassID = InstantInfo(id)
    return classID == 2 and subclassID == 20
end

local function IsFishingRodItem(self, id, instant)
    if not id or id == 0 then return false end
    local classID, subclassID
    local location, icon
    if instant then classID, subclassID = instant.classID, instant.subclassID
    else location, icon, classID, subclassID = InstantInfo(id) end
    if classID ~= nil and subclassID ~= nil then return classID == 2 and subclassID == 20 end
    local configured = self.db.gearItems and self.db.gearItems[16]
    return configured and configured.id == id or false
end

-- Return nil if item data is unavailable; an unknown main hand must not be
-- mistaken for a missing pole while a cast is still being resolved.
function FF:FishingRodEquippedNow()
    if not GetInventoryItemID then return nil end
    local id = GetInventoryItemID("player", 16)
    if not id or id == 0 then return false end
    local _, _, classID, subclassID = InstantInfo(id)
    if classID ~= nil and subclassID ~= nil then return classID == 2 and subclassID == 20 end
    local configured = self.db and self.db.gearItems and self.db.gearItems[16]
    if configured and configured.id == id then return true end
    return nil
end

local function IsConfirmedWeaponItem(id)
    if type(id) ~= "number" or id <= 0 then return false end
    local _, _, classID, subclassID = InstantInfo(id)
    -- Uncached item data is not proof that a newly equipped pole is a normal
    -- weapon. Wait for item info rather than poisoning the saved restore set.
    return classID == 2 and subclassID ~= nil and subclassID ~= 20
end

local function IsConfirmedNormalWeapon(self, slot, id)
    if IsFishingWeapon(self, slot, id) then return false end
    return IsConfirmedWeaponItem(id)
end

function FF:TryFishingRodAutoOpen()
    local id = self.rodAutoOpenPending
    if not id or not self.bar then return end
    if self.db and self.db.autoOpenFishingBar == false then
        self.rodAutoOpenPending = nil
        return
    end
    if not GetInventoryItemID or GetInventoryItemID("player", 16) ~= id then
        self.rodAutoOpenPending = nil
        return
    end
    if InCombatLockdown and InCombatLockdown() then return end
    self.rodAutoOpenPending = nil
    if not self.bar:IsShown() then self.bar:Show() end
end

function FF:CheckFishingRodAutoOpen(force)
    if not self.db or not self.bar or not GetInventoryItemID then return end
    if self.db.autoOpenFishingBar == false then
        self.rodAutoOpenPending, self.rodAutoOpenItemInfo = nil, nil
        return
    end
    local id = GetInventoryItemID("player", 16) or 0
    -- Ignore repeated equipment notifications. In particular, manually closing
    -- the bar while the same rod is worn must not immediately reopen it.
    if not force and self.rodAutoOpenMainHand == id then return end
    self.rodAutoOpenMainHand = id
    self.rodAutoOpenPending, self.rodAutoOpenItemInfo = nil, nil
    self.fishingRodEquipped = false
    if id == 0 then return end
    local _, _, classID, subclassID = InstantInfo(id)
    if classID == nil or subclassID == nil then
        local configured = self.db.gearItems and self.db.gearItems[16]
        self.fishingRodEquipped = configured and configured.id == id or false
        -- Ask once for uncached item data; the existing item-info event retries
        -- only this equipped item. Never scan bags or inspect tooltip text.
        self.rodAutoOpenItemInfo = id
        local getter = GetItemInfo or (C_Item and C_Item.GetItemInfo)
        if getter then
            local info = { getter(id) }
            classID, subclassID = info[12], info[13]
        end
        if classID == nil or subclassID == nil then return end
        self.rodAutoOpenItemInfo = nil
    end
    -- Use the actual weapon category, rather than the configured gear list:
    -- putting an ordinary weapon in the fishing set must not auto-open it.
    self.fishingRodEquipped = classID == 2 and subclassID == 20
    if classID == 2 and subclassID == 20 then
        self.rodAutoOpenPending = id
        self:TryFishingRodAutoOpen()
    end
end

function FF:SetFishingRodAutoOpen(enabled)
    enabled = enabled == true
    if self.db.autoOpenFishingBar == enabled then return end
    self.db.autoOpenFishingBar = enabled
    if enabled then self:CheckFishingRodAutoOpen(true)
    else self.rodAutoOpenPending, self.rodAutoOpenItemInfo = nil, nil end
end

local function FishingWeaponEquipped(self)
    if not GetInventoryItemID then return false end
    for slot = 16, 17 do
        if IsFishingWeapon(self, slot, GetInventoryItemID("player", slot)) then return true end
    end
    return false
end

function FF:NextFishingAction()
    -- Do not restart a lure application or equip items while an item-use cast
    -- is running. Native cast events refresh readiness when it finishes.
    if UnitCastingInfo and UnitCastingInfo("player") then return "wait" end
    if UnitChannelInfo and UnitChannelInfo("player") and not self:IsFishingChannelActive() then return "wait" end
    if self.pendingFishingGear or self.pendingGearRestore then return "wait" end
    if not self.db.autoEquipGear and not self.db.autoEquipLures then return "cast" end
    if self.db.autoEquipGear and next(self:GetAvailableFishingGear()) and not self:AvailableFishingGearEquipped() then
        local blocked = self.gearSwapBlocked
        if blocked and blocked.db == self.db and blocked.spec == CurrentGearSpecKey(self) then
            -- Do not replay a failed outfit on every fishing press. A worn
            -- pole can still fish; otherwise Gear is the explicit retry.
            local main = GetInventoryItemID and GetInventoryItemID("player", 16)
            return IsFishingRodItem(self, main) and "cast" or "wait"
        end
        return "gear"
    end
    if not self.db.autoEquipLures then return "cast" end
    -- The managed lure macro targets slot 16, so only a main-hand pole is valid.
    if not GetInventoryItemID or not IsFishingWeapon(self, 16, GetInventoryItemID("player", 16)) then return "cast" end
    local remaining = self:LureSeconds()
    if remaining == nil or remaining > 0 then return "cast" end
    if self.lureApplyPendingAt and GetTime() - self.lureApplyPendingAt < 1 then return "wait" end
    for _, entry in ipairs(self.availableLures or {}) do
        if entry.id == self.db.lure and self.lureButton and self.lureButton:GetAttribute("type1") == "macro" then
            return "lure", self.lureButton:GetAttribute("macro1")
        end
    end
    return "cast"
end

local function RememberedWeapons(self, specKey)
    local saved = self.db.normalWeaponsBySpec[specKey]
    if type(saved) == "table" and type(saved[16]) == "table"
        and ((saved[16].id == 0 and type(saved[17]) == "table"
            and type(saved[17].id) == "number" and saved[17].id >= 0)
            or IsConfirmedNormalWeapon(self, 16, saved[16].id))
        and not (saved[17] and IsFishingRodItem(self, saved[17].id)) then
        return saved
    end
end

local function EquipmentSets()
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs or not C_EquipmentSet.GetItemIDs then return nil end
    local ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
    if not ok or type(ids) ~= "table" then return nil end
    local sets = {}
    for _, setID in ipairs(ids) do
        local read, items = pcall(C_EquipmentSet.GetItemIDs, setID)
        if read and type(items) == "table" then
            local ignored, locations
            if C_EquipmentSet.GetIgnoredSlots then
                local ok, result = pcall(C_EquipmentSet.GetIgnoredSlots, setID)
                if ok and type(result) == "table" then ignored = result end
            end
            if C_EquipmentSet.GetItemLocations then
                local ok, result = pcall(C_EquipmentSet.GetItemLocations, setID)
                if ok and type(result) == "table" then locations = result end
            end
            sets[#sets + 1] = { id = setID, items = items, ignored = ignored, locations = locations }
        end
    end
    return sets
end

local function NormalSetWeapons(self, set)
    local main = set.items[16]
    if not (set.ignored and set.ignored[16]) and set.locations and set.locations[16] == 0
        and (main == nil or (type(main) == "number" and main <= 0)) then
        main = 0
    elseif type(main) ~= "number" or not IsConfirmedNormalWeapon(self, 16, main) then return nil end
    local off = set.items[17]
    if type(off) == "number" and off > 0 then
        if IsFishingRodItem(self, off) then return nil end
    elseif not (set.ignored and set.ignored[17]) and set.locations and set.locations[17] == 0 then
        off = 0
    else
        off = nil
    end
    -- An ignored/unknown offhand is not proof that both hands were empty.
    if main == 0 and off == nil then return nil end
    return { [16] = { id = main }, [17] = off and { id = off } or nil }
end

local function SetMatchesWornGear(self, set)
    local compared = 0
    for slot = 1, 19 do
        if slot ~= 16 and slot ~= 17 then
            local expected = set.items[slot]
            if type(expected) == "number" and expected > 0 then
                local current = GetInventoryItemID and GetInventoryItemID("player", slot)
                local fishing = self.db.gearItems[slot]
                if not (fishing and fishing.id == current) then
                    if current ~= expected then return nil end
                    compared = compared + 1
                end
            end
        end
    end
    return compared
end

local function ResolveNormalWeapons(self, specKey)
    local sets = EquipmentSets()
    if not sets or #sets == 0 then return RememberedWeapons(self, specKey) end

    local candidates = {}
    local rememberedID = self.db.normalGearSetBySpec[specKey]
    local normalSetCount = 0
    for _, set in ipairs(sets) do
        local weapons = NormalSetWeapons(self, set)
        if weapons then normalSetCount = normalSetCount + 1 end
        local matches = weapons and SetMatchesWornGear(self, set)
        if matches ~= nil then
            candidates[#candidates + 1] = { id = set.id, weapons = weapons }
        end
    end

    if normalSetCount == 0 then return RememberedWeapons(self, specKey) end
    if #candidates == 0 then return nil end
    local function WithRememberedLinks(candidate)
        local weapons = candidate.weapons
        local saved = self.db.normalWeaponsBySet[specKey .. ":" .. tostring(candidate.id)]
        if type(saved) ~= "table" then return weapons end
        local linked = {}
        for slot = 16, 17 do
            local entry = weapons[slot]
            if entry then
                local previous = saved[slot]
                -- Availability may be temporary. Never discard a remembered
                -- variant merely because its link changed display fields or
                -- the original copy is banked while another same-ID copy exists.
                linked[slot] = previous and previous.id == entry.id and previous or entry
            end
        end
        return linked
    end
    for _, candidate in ipairs(candidates) do
        if candidate.id == rememberedID then return WithRememberedLinks(candidate) end
    end

    local recent = RememberedWeapons(self, specKey)
    if recent then
        local matched, count = nil, 0
        for _, candidate in ipairs(candidates) do
            local off = candidate.weapons[17]
            if candidate.weapons[16].id == recent[16].id
                and (not off or (recent[17] and off.id == recent[17].id)) then
                matched, count = candidate, count + 1
            end
        end
        if count == 1 then return WithRememberedLinks(matched) end
    end

    if C_EquipmentSet.GetEquipmentSetAssignedSpec and GetSpecialization then
        local ok, currentSpec = pcall(GetSpecialization)
        if ok and type(currentSpec) == "number" then
            local assigned, count = nil, 0
            for _, candidate in ipairs(candidates) do
                local read, spec = pcall(C_EquipmentSet.GetEquipmentSetAssignedSpec, candidate.id)
                if read and spec == currentSpec then
                    assigned, count = candidate, count + 1
                end
            end
            if count == 1 then return WithRememberedLinks(assigned) end
        end
    end

    local first = candidates[1].weapons
    for index = 2, #candidates do
        local other = candidates[index].weapons
        if first[16].id ~= other[16].id
            or (first[17] and first[17].id) ~= (other[17] and other[17].id) then
            return nil
        end
    end
    return WithRememberedLinks(candidates[1])
end

function FF:RememberEquippedEquipmentSet(setID)
    if self.combatWeaponRestore then return end
    if not self.db or not GetInventoryItemID then return end
    local main = GetInventoryItemID("player", 16) or 0
    if (main ~= 0 and not IsConfirmedNormalWeapon(self, 16, main))
        or IsFishingRodItem(self, GetInventoryItemID("player", 17)) then return end
    local sets = EquipmentSets()
    if not sets then return end
    local chosen
    for _, set in ipairs(sets) do
        local weapons = NormalSetWeapons(self, set)
        if weapons then
            local off = weapons[17]
            local wornOff = GetInventoryItemID and GetInventoryItemID("player", 17)
            if set.id == setID and main == weapons[16].id
                and (not off or wornOff == (off.id ~= 0 and off.id or nil)) then
                chosen = set.id
                break
            end
            if C_EquipmentSet.GetEquipmentSetInfo then
                local ok, _, _, _, isEquipped = pcall(C_EquipmentSet.GetEquipmentSetInfo, set.id)
                if ok and isEquipped then chosen = set.id end
            end
        end
    end
    self.db.normalGearSetBySpec[CurrentGearSpecKey(self)] = chosen
    return chosen
end

local function WarnUnknownNormalWeapons(self)
    local message = FF:LocalizedText("gear.normal-unidentified")
    self:Print(message)
    if not StaticPopupDialogs or not StaticPopup_Show then return end
    local key = "FOREVER_FISHING_UNKNOWN_WEAPONS"
    if not StaticPopupDialogs[key] then
        StaticPopupDialogs[key] = {
            text = FF:LocalizedText("gear.normal-unidentified-popup"),
            button1 = FF:LocalizedText("common.okay"),
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end
    StaticPopup_Show(key)
end

function FF:RememberNormalWeapons(setID)
    if self.combatWeaponRestore then return end
    if self.gearWorldInterrupted then return end
    if not self.db or not GetInventoryItemID or self.pendingFishingGear or self.pendingGearRestore then return end
    local main = GetInventoryItemID("player", 16) or 0
    -- Empty hands are valid normal gear, but not while a transfer/combat or
    -- active fishing swap could make that emptiness only an intermediate state.
    if main == 0 and (self.db.gearSwapActive or (CursorHasItem and CursorHasItem())
        or (InCombatLockdown and InCombatLockdown())) then return end
    if main ~= 0 and not IsConfirmedNormalWeapon(self, 16, main) then return end
    local off = GetInventoryItemID and GetInventoryItemID("player", 17)
    if IsFishingWeapon(self, 17, off) then
        -- An ordinary selected offhand already known as normal must not block
        -- a complete manual weapon change. A different fishing offhand still
        -- marks a partial loadout and cannot replace the original snapshot.
        local known = self.db.gearRestore or self.db.normalWeaponsBySpec[CurrentGearSpecKey(self)]
        local normalOff = type(known) == "table" and known[17]
        if IsFishingRodItem(self, off) or not (normalOff and normalOff.id == off) then return end
    end
    if self.db.gearSwapActive then
        local previousOff = self.db.gearRestore and self.db.gearRestore[17]
        local currentOff = GetInventoryItemID("player", 17)
        local equipLoc = InstantInfo(main)
        -- Replacing a pole with a one-hand weapon can leave the off-hand empty
        -- until the player equips it. Keep the original pair in that interval.
        if previousOff and previousOff.id and previousOff.id ~= 0
            and not currentOff and equipLoc ~= "INVTYPE_2HWEAPON" then return end
        -- A spec change or manual weapon change replaced the fishing pole.
        -- The old swap no longer describes the weapons currently equipped.
        if self.db.gearItems[16] or self.db.gearItems[17] or not next(self.db.gearItems) then
            -- A complete manual weapon choice wins, but does not discard
            -- original armour still replaced by the fishing outfit.
            local restore = self.db.gearRestore
            if restore then restore[16], restore[17] = nil, nil end
            if not restore or not next(restore) then
                self.db.gearRestore = nil
                self.db.gearSwapActive = nil
                self.db.gearSwapSpec = nil
                self.db.gearSwapOwner = nil
            else
                self.db.gearSwapSpec = CurrentGearSpecKey(self)
            end
            self.combatWeaponPlanDirty = true
        else
            return
        end
    end
    local snapshot = CaptureSlots({ [16] = true, [17] = true })
    local specKey = CurrentGearSpecKey(self)
    self.db.normalWeaponsBySpec[specKey] = snapshot
    local equippedSetID = self:RememberEquippedEquipmentSet(setID)
    if equippedSetID then
        self.db.normalWeaponsBySet[specKey .. ":" .. tostring(equippedSetID)] = snapshot
    end
    if self.SyncCombatWeaponRestore then self:SyncCombatWeaponRestore() end
end

function FF:QueueNormalWeaponCapture(setID)
    if self.combatWeaponRestore then return end
    if type(setID) == "number" then self.normalWeaponSetID = setID end
    self.normalWeaponCaptureToken = (self.normalWeaponCaptureToken or 0) + 1
    local token = self.normalWeaponCaptureToken
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            if self.normalWeaponCaptureToken == token then
                local equippedSetID = self.normalWeaponSetID
                self.normalWeaponSetID = nil
                self:RememberNormalWeapons(equippedSetID)
            end
        end)
    else
        local equippedSetID = self.normalWeaponSetID
        self.normalWeaponSetID = nil
        self:RememberNormalWeapons(equippedSetID)
    end
end

local function ResolveSlot(equipLoc, items)
    local slot = EQUIP_SLOTS[equipLoc]
    if equipLoc == "INVTYPE_FINGER" and items[11] then slot = 12 end
    if equipLoc == "INVTYPE_TRINKET" and items[13] then slot = 14 end
    if equipLoc == "INVTYPE_WEAPON" and items[16] then slot = 17 end
    return slot
end

local function FishingBonus(text)
    if type(text) ~= "string" then return 0 end
    return tonumber(text:match("%+(%d+)%s+fishing"))
        or tonumber(text:match("fishing skill[^%d]+(%d+)"))
        or tonumber(text:match("increases fishing[^%d]+(%d+)"))
        or tonumber(text:match("fishing%s+%+(%d+)"))
        or 0
end

-- Hyperlink tooltips retain permanent enchants but exclude the worn rod's
-- temporary lure. Cache only in this discovery pass, never in saved settings.
local function PermanentFishingBonus(link, cache)
    if (issecretvalue and issecretvalue(link)) or type(link) ~= "string" then return nil end
    if cache[link] ~= nil then return cache[link] ~= false and cache[link] or nil end
    cache[link] = false
    if issecretvalue and issecretvalue(C_TooltipInfo) then return nil end
    local getter = type(C_TooltipInfo) == "table" and rawget(C_TooltipInfo, "GetHyperlink")
    if (issecretvalue and issecretvalue(getter)) or type(getter) ~= "function" then return nil end
    local ok, info = pcall(getter, link)
    if not ok or (issecretvalue and issecretvalue(info)) or type(info) ~= "table" then return nil end
    local lines = rawget(info, "lines")
    if (issecretvalue and issecretvalue(lines)) or type(lines) ~= "table" or #lines < 2 then return nil end
    local total, readable, matched = 0, false, false
    for _, line in ipairs(lines) do
        if (issecretvalue and issecretvalue(line)) or type(line) ~= "table" then return nil end
        for _, key in ipairs({ "leftText", "rightText" }) do
            local text = rawget(line, key)
            if issecretvalue and issecretvalue(text) then return nil end
            if type(text) == "string" and text ~= "" then
                if text == RETRIEVING_ITEM_INFO then return nil end
                readable = true
                local plain = text:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                local bonus = not plain:find("requires", 1, true) and not plain:match("^use:") and FishingBonus(plain) or 0
                if ValidGearBonus(bonus) == nil then return nil end
                if bonus > 0 then total, matched = total + bonus, true end
            end
        end
    end
    -- Unrecognised/localised text is not evidence of a zero Fishing bonus.
    local locale
    if type(GetLocale) == "function" and not (issecretvalue and issecretvalue(GetLocale)) then
        local localeOK, value = pcall(GetLocale)
        if localeOK and not (issecretvalue and issecretvalue(value)) then locale = value end
    end
    if readable and ValidGearBonus(total) and (matched or locale == "enUS" or locale == "enGB") then cache[link] = total; return total end
end

local function IsFishingGear(id, name, equipLoc, text, classID, subclassID)
    if not id or not equipLoc or equipLoc == "" then return false end
    if classID == 2 and subclassID == 20 then return true end
    text = type(text) == "string" and text:lower() or ""
    name = type(name) == "string" and name:lower() or ""
    return text:find("fishing skill", 1, true)
        or text:find("increases fishing", 1, true)
        or text:find("+ fishing", 1, true)
        or name:find("fishing", 1, true)
        or name:find("angler", 1, true)
        or FishingBonus(text) > 0
end

function FF:ScanFishingGear(scan)
    if type(self.db.gearItems) ~= "table" then return end
    self.fishingRodEquipped = IsFishingRodItem(self, GetInventoryItemID and GetInventoryItemID("player", 16))
    local found, seen, permanentBonuses, owned = {}, {}, {}, {}
    local rodInBags = false
    local function Add(id, link, icon, text, equippedSlot, instant)
        id = tonumber(id)
        if not id then return end
        local name, itemLink, quality, equipLoc, itemIcon = ItemInfo(id)
        local instantLoc, instantIcon, classID, subclassID
        if instant then
            instantLoc, instantIcon, classID, subclassID = instant.equipLoc, instant.instantIcon, instant.classID, instant.subclassID
        else instantLoc, instantIcon, classID, subclassID = InstantInfo(id) end
        if not equipLoc or equipLoc == "" then equipLoc = instantLoc end
        owned[id] = owned[id] or {}
        owned[id][#owned[id] + 1] = { link = link or itemLink, slot = equippedSlot,
            isFishingRod = classID == 2 and subclassID == 20 }
        if not IsFishingGear(id, name, equipLoc, text, classID, subclassID) then return end
        local slot = equippedSlot or ResolveSlot(equipLoc, self.db.gearItems)
        if not slot then return end
        local key = tostring(id) .. ":" .. tostring(slot)
        local bonus = FishingBonus(text)
        local baseBonus = PermanentFishingBonus(link or itemLink, permanentBonuses)
        local prior = seen[key]
        if prior and (baseBonus == nil or (prior.baseFishingBonus ~= nil and baseBonus <= prior.baseFishingBonus)) then return end
        local entry = {
            id = id, link = link or itemLink, name = name, quality = quality or 1,
            icon = icon or itemIcon or instantIcon, equipLoc = equipLoc, slot = slot,
            bonus = bonus, equipped = equippedSlot ~= nil,
            baseFishingBonus = baseBonus,
            isFishingRod = classID == 2 and subclassID == 20,
            score = (classID == 2 and subclassID == 20 and 100000 or 0) + bonus * 100 + (quality or 1),
        }
        if prior then
            for index, item in ipairs(found) do if item == prior then found[index] = entry; break end end
        else found[#found + 1] = entry end
        seen[key] = entry
    end

    for slot = 1, 19 do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if id then Add(id, GetInventoryItemLink and GetInventoryItemLink("player", slot), GetInventoryItemTexture and GetInventoryItemTexture("player", slot), InventoryTooltipText(slot), slot) end
    end
    for _, item in ipairs(scan or BagScan()) do
        local instant = BagScanInstant(item)
        if IsFishingRodItem(self, item.id, instant) then rodInBags = true end
        local equipLoc = instant.equipLoc
        if equipLoc and equipLoc ~= "" then
            Add(item.id, item.link, item.icon, BagScanText(item), nil, instant)
        end
    end
    table.sort(found, function(a, b)
        if a.slot ~= b.slot then return a.slot < b.slot end
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name
    end)
    self.availableFishingGear = found
    self.availableGearOwned = owned
    self.fishingRodInBags = rodInBags

    if not self.combatWeaponRestore and not self.pendingFishingGear
        and not self.pendingGearRestore and not (InCombatLockdown and InCombatLockdown()) then
        self:AdoptOwnedLegacyFishingGear(owned)
        local best = {}
        for _, entry in ipairs(found) do
            if not self.db.gearIgnored[entry.id] and entry.baseFishingBonus ~= nil then
                local previous = best[entry.slot]
                if not previous or entry.baseFishingBonus > previous.baseFishingBonus then best[entry.slot] = entry end
            end
        end
        for _, entry in ipairs(found) do
            local current = self.db.gearItems[entry.slot]
            local candidate = best[entry.slot] or entry
            local currentBonus = current and ValidGearBonus(current.baseFishingBonus)
            if current then
                local linkedBonus = PermanentFishingBonus(current.link, permanentBonuses)
                local observed = seen[tostring(current.id) .. ":" .. tostring(entry.slot)]
                if linkedBonus ~= nil then currentBonus = linkedBonus
                elseif currentBonus == nil and observed then currentBonus = observed.baseFishingBonus end
            end
            -- Same-slot upgrades reuse the held normal-gear snapshot. Do not add
            -- new slots during an active swap or change pending/combat plans.
            if not self.db.gearIgnored[candidate.id] and (not current and not self.db.gearSwapActive or current and current.detected == true
                and currentBonus ~= nil and candidate.baseFishingBonus ~= nil
                and candidate.baseFishingBonus > currentBonus) then
                self.db.gearItems[entry.slot] = {
                    id = candidate.id, link = candidate.link, name = candidate.name, icon = candidate.icon,
                    slot = entry.slot, equipLoc = candidate.equipLoc, detected = true,
                    baseFishingBonus = candidate.baseFishingBonus,
                }
                self.combatWeaponPlanDirty = true
            end
        end
    end
    self:RefreshAvailableFishingGear()
    if self.gearPicker and self.gearPicker:IsShown() then self:RefreshGearPicker() end
end

function FF:ScanFishingInventory()
    local scan = BagScan()
    self:ScanLures(scan)
    self:ScanFishingGear(scan)
    return scan
end

function FF:AddFishingGearItem(id, selectedLink, selectedSlot)
    if InCombatLockdown and InCombatLockdown() then self:Print(FF:LocalizedText("gear.change-combat")); return false end
    self.combatWeaponPlanDirty = true
    id = tonumber(id)
    local name, link, _, equipLoc, icon = ItemInfo(id)
    local slot = selectedSlot or ResolveSlot(equipLoc, self.db.gearItems)
    if not slot then self:Print(FF:LocalizedText("gear.invalid-slot")); return false end
    self.db.gearIgnored[id] = nil
    if not selectedLink then
        for _, entry in ipairs(self.availableFishingGear or {}) do
            if entry.id == id and entry.slot == slot then selectedLink = entry.link; break end
        end
    end
    self:CancelGearOperation()
    self.gearSwapBlocked = nil
    if self.db.gearSwapActive and self.db.gearRestore then
        local slots = { [slot] = true }
        if slot == 16 then slots[17] = true end
        for originalSlot, entry in pairs(CaptureSlots(slots)) do
            if not self.db.gearRestore[originalSlot] then self.db.gearRestore[originalSlot] = entry end
        end
    end
    self.db.gearItems[slot] = { id = id, link = selectedLink or link, name = name, icon = icon, slot = slot, equipLoc = equipLoc }
    if self.fishingGearProfileDB == self.db and self.fishingGearProfile then
        self.fishingGearProfile.legacyImported[slot] = true
    end
    self:RefreshAvailableFishingGear()
    self:RefreshUI()
    self:Print(FF:LocalizedText("gear.added-message",name,GearSlotLabel(slot)))
    return true
end

function FF:RemoveFishingGearItem(slot)
    if InCombatLockdown and InCombatLockdown() then self:Print(FF:LocalizedText("gear.change-combat")); return end
    self.combatWeaponPlanDirty = true
    local removed = self.db.gearItems[slot]
    if removed and removed.id then self.db.gearIgnored[removed.id] = true end
    self:CancelGearOperation()
    self.gearSwapBlocked = nil
    self.db.gearItems[slot] = nil
    if self.fishingGearProfileDB == self.db and self.fishingGearProfile then
        self.fishingGearProfile.legacyImported[slot] = true
    end
    -- Selection is a preference, not permission to erase original gear.
    self:RefreshAvailableFishingGear()
    self:RefreshUI()
    if self.gearPicker and self.gearPicker:IsShown() then self:RefreshGearPicker() end
end

local function FishingGearItemEquipped(entry, slot)
    return GearItemEquipped(entry, slot)
end

-- Resolve only on existing inventory scans or explicit selection changes. The
-- saved set remains authoritative; a missing slot's fallback is never saved.
function FF:RefreshAvailableFishingGear()
    if not self.availableFishingGear then
        self.availableGearOwner, self.availableGearSet = nil, nil
        return
    end
    local resolved, missing, rod = {}, false, false
    for slot, preferred in pairs(self.db.gearItems or {}) do
        local match, best
        local enchant = type(preferred.link) == "string" and tonumber(preferred.link:match("item:%d+:(%d+)"))
        -- Keep all owned copies for identity, even when ranking collapses a
        -- stronger same-ID variant or the user manually added ordinary gear.
        for _, item in ipairs((self.availableGearOwned or {})[preferred.id] or {}) do
            local itemEnchant = type(item.link) == "string" and tonumber(item.link:match("item:%d+:(%d+)"))
            if (not item.slot or item.slot == slot) and (not enchant or enchant == 0 or itemEnchant == enchant) then match = item; break end
        end
        for _, item in ipairs(self.availableFishingGear) do
            if item.slot == slot and not (self.db.gearIgnored or {})[item.id] then
                local itemEnchant = type(item.link) == "string" and tonumber(item.link:match("item:%d+:(%d+)"))
                if item.id == preferred.id and (not enchant or enchant == 0 or itemEnchant == enchant) then match = item end
                if not best or (item.baseFishingBonus ~= nil and (best.baseFishingBonus == nil
                    or item.baseFishingBonus > best.baseFishingBonus)) then best = item end
            end
        end
        if match then
            resolved[slot] = preferred
            if slot == 16 and match.isFishingRod then rod = true end
        else
            missing = true
            if best then
                resolved[slot] = best
                if slot == 16 and best.isFishingRod then rod = true end
            end
        end
    end
    self.availableGearOwner, self.availableGearSelection, self.availableGearSet = self.db, self.db.gearItems, resolved
    self.availableGearMissing, self.availableGearHasRod = missing, rod
    if (not missing and self.fishingGearNoticeState == "fallback")
        or ((self.fishingRodEquipped or self.fishingRodInBags) and self.fishingGearNoticeState == "noRod") then
        self.fishingGearNoticeState = nil
        local notice = self.masterChefPreparationNotice
        if notice and notice.kind == "gear" then notice:Hide() end
    end
end

function FF:GetAvailableFishingGear()
    if self.availableGearOwner == self.db and self.availableGearSelection == self.db.gearItems
        and self.availableGearSet then return self.availableGearSet end
    return self.db.gearItems or {}
end

function FF:AvailableFishingGearEquipped()
    local gear = self:GetAvailableFishingGear()
    if not next(gear) then return false end
    for slot, entry in pairs(gear) do
        if not FishingGearItemEquipped(entry, slot) then return false end
    end
    return true
end

function FF:NotifyAvailableFishingGear()
    if not self.ShowFishingGearStatus then return end
    if not self.fishingRodEquipped and not self.fishingRodInBags
        and not (self.FishingRodEquippedNow and self:FishingRodEquippedNow()) then
        return self:ShowFishingGearStatus("noRod")
    end
    if self.availableGearOwner == self.db and self.availableGearMissing
        and self.availableGearHasRod and self:AvailableFishingGearEquipped() then
        return self:ShowFishingGearStatus("fallback")
    end
end

function FF:CustomGearEquipped()
    if not next(self.db.gearItems or {}) then return false end
    for slot, entry in pairs(self.db.gearItems) do
        if not FishingGearItemEquipped(entry, slot) then return false end
    end
    return true
end

local function CopyGearSnapshot(snapshot)
    local copy = {}
    for slot, entry in pairs(snapshot or {}) do
        copy[slot] = { id = entry.id, link = entry.link,
            fishingID = entry.fishingID, fishingLink = entry.fishingLink }
    end
    return copy
end

function FF:RecoverCharacterGearSnapshot()
    -- SavedVariables are account-wide. Parking a foreign transaction preserves
    -- its armour/weapon originals instead of discarding them on another login.
    -- Only one active snapshot is exposed to the existing gear systems.
    local owner = self:GearCharacterKey()
    local parked = self.db.gearRestoresByCharacter
    local foreign = self.db.gearSwapOwner
    local held = self.db.combatWeaponRestore
    local function Park(key, snapshot, spec, combat)
        if type(key) ~= "string" or type(snapshot) ~= "table" then return end
        if type(parked) ~= "table" then parked = {}; self.db.gearRestoresByCharacter = parked end
        parked[key] = { snapshot = snapshot, spec = spec, combat = combat }
    end
    if foreign and foreign ~= owner then
        Park(foreign, self.db.gearRestore, self.db.gearSwapSpec,
            type(held) == "table" and held.owner == foreign and held or nil)
        self.db.gearRestore, self.db.gearSwapActive = nil, nil
        self.db.gearSwapSpec, self.db.gearSwapOwner = nil, nil
    end
    if type(held) == "table" and held.owner ~= owner then
        if type(held.owner) == "string" then
            local record = type(parked) == "table" and parked[held.owner]
            if type(record) == "table" then record.combat = held
            else Park(held.owner, held.snapshot, held.spec, held) end
        end
        self.db.combatWeaponRestore = nil
    end
    local record = type(parked) == "table" and parked[owner]
    if type(record) == "table" and type(record.snapshot) == "table"
        and (not self.db.gearRestore or not next(self.db.gearRestore)) then
        self.db.gearRestore, self.db.gearSwapActive = record.snapshot, true
        self.db.gearSwapOwner, self.db.gearSwapSpec = owner, record.spec
        self.db.combatWeaponRestore = record.combat
        parked[owner] = nil
    end
end

function FF:RecoverCombatWeaponRestore()
    local held = self.db.combatWeaponRestore
    local valid = type(held) == "table" and held.owner == self:GearCharacterKey()
        and type(held.spec) == "string" and type(held.snapshot) == "table"
    if valid then
        for slot, entry in pairs(held.snapshot) do
            if type(slot) ~= "number" or slot < 1 or slot > 19
                or type(entry) ~= "table" or type(entry.id) ~= "number" or entry.id < 0
                or (entry.link ~= nil and type(entry.link) ~= "string") then valid = false; break end
        end
        local main = held.snapshot[16]
        valid = valid and type(main) == "table" and type(main.id) == "number" and main.id > 0
    end
    if not valid then
        self.db.combatWeaponRestore = nil
        held = nil
    end
    self.combatWeaponRestore = held
    self.combatWeaponPlanDirty = true
end

function FF:SyncCombatWeaponRestore()
    if not self.db or (InCombatLockdown and InCombatLockdown()) then return end
    local owner, spec = self:GearCharacterKey(), CurrentGearSpecKey(self)
    local saved = self.combatWeaponRestore
    local inputs = self.combatWeaponPlanInputs
    local normal = self.db.normalWeaponsBySpec and self.db.normalWeaponsBySpec[spec]
    local fishingName = self:FishingName()
    if not self.combatWeaponPlanDirty and inputs and inputs.restore == self.db.gearRestore
        and inputs.normal == normal and inputs.gear == self.db.gearItems and inputs.held == saved
        and inputs.spec == spec and inputs.autoRestore == self.db.autoRestoreGear and inputs.fishingName == fishingName
        and inputs.gearButton == self.gearButton and inputs.closeButton == self.closeButton then return end
    self.combatWeaponPlanDirty = nil
    self.combatWeaponPlanInputs = { restore = self.db.gearRestore, normal = normal,
        gear = self.db.gearItems, held = saved, spec = spec, autoRestore = self.db.autoRestoreGear, fishingName = fishingName,
        gearButton = self.gearButton, closeButton = self.closeButton }
    local snapshot
    if saved and saved.owner == owner and saved.spec == spec then
        snapshot = CopyGearSnapshot(saved.snapshot)
    elseif not self.db.gearSwapOwner or self.db.gearSwapOwner == owner then
        if type(self.db.gearRestore) == "table" and next(self.db.gearRestore) then
            snapshot = CopyGearSnapshot(self.db.gearRestore)
        end
        local weapons = snapshot and snapshot[16]
            and IsConfirmedWeaponItem(snapshot[16].id)
            and not (snapshot[17] and IsFishingRodItem(self, snapshot[17].id))
            and (not self.db.gearSwapSpec or self.db.gearSwapSpec == spec) and snapshot
            or ResolveNormalWeapons(self, spec)
        if weapons then
            if not snapshot then
                local slots = { [16] = true, [17] = true }
                for slot in pairs(self.db.gearItems or {}) do slots[slot] = true end
                snapshot = CaptureSlots(slots)
            end
            snapshot[16], snapshot[17] = weapons[16], weapons[17]
        else snapshot = nil end
    end
    -- Empty-hand cleanup stays outside combat; no offhand-only restore plan.
    if snapshot and snapshot[16] and snapshot[16].id == 0 then snapshot = nil end
    local lines = {}
    for slot = 16, 17 do
        local entry = snapshot and snapshot[slot]
        if entry and type(entry.id) == "number" and entry.id > 0 then
            -- Retain the exact item payload for enchanted/duplicate weapons.
            local item = type(entry.link) == "string" and
                (entry.link:match("|H(item:[^|]+)|h") or entry.link)
            if not item or not item:match("^item:[%d:%-]+$") then item = "item:" .. entry.id end
            lines[#lines + 1] = "/equipslot [combat] " .. slot .. " " .. item
        end
    end
    -- One hardware click stops only Fishing before restoring combat weapons.
    -- A different or not-yet-stopped channel must leave this sequence untouched.
    local macro = #lines > 0 and ("/stopcasting [combat,channeling:" .. fishingName
        .. "]\n/stopmacro [combat,channeling]\n" .. table.concat(lines, "\n")) or nil
    self.combatWeaponPlan = macro and { snapshot = CopyGearSnapshot(snapshot), owner = owner, spec = spec } or nil
    for _, button in ipairs({ self.gearButton, self.closeButton }) do
        if button and button.combatWeaponButton == true then
            local text = (button ~= self.closeButton or self.db.autoRestoreGear) and macro or nil
            if button:GetAttribute("macrotext1") ~= text then button:SetAttribute("macrotext1", text) end
        end
    end
end

function FF:BeginCombatWeaponRestore(button)
    if not (InCombatLockdown and InCombatLockdown()) then return end
    if not button or button.combatWeaponButton ~= true or not button:GetAttribute("macrotext1") then
        self:Print(FF:LocalizedText("gear.combat-unprepared"))
        return
    end
    local plan = self.combatWeaponPlan
    if not plan then return end
    -- Set the learning guard BEFORE the native secure click can emit equipment
    -- events. It survives combat and delayed captures until a full restore.
    self.combatWeaponRestore = self.combatWeaponRestore or plan
    -- Transaction metadata only: retain the already prepared snapshot across
    -- reload without modifying any remembered normal/fishing gear records.
    self.db.combatWeaponRestore = self.combatWeaponRestore
    self.normalWeaponCaptureToken = (self.normalWeaponCaptureToken or 0) + 1
    self.normalWeaponSetID = nil
    self:CancelGearOperation()
    self:Print(FF:LocalizedText("gear.combat-attempt"))
end

function FF:ResumeCombatGearSnapshot()
    local held = self.combatWeaponRestore
    if not held then return true end
    if held.owner ~= self:GearCharacterKey() then
        self:Print(FF:LocalizedText("gear.combat-foreign-owner"))
        return false
    end
    if not self.db.gearRestore or not next(self.db.gearRestore) then
        self.db.gearRestore = CopyGearSnapshot(held.snapshot)
        self.db.gearSwapActive = true
        self.db.gearSwapOwner, self.db.gearSwapSpec = held.owner, held.spec
    end
    return true
end

-- One finite, serialized gear operation owns native requests and delayed work.
-- The original saved snapshot is not cleared by cancellation or rejection.
local function SnapshotEquipped(snapshot)
    if CursorHasItem and CursorHasItem() then return false end
    for slot, entry in pairs(snapshot or {}) do
        if not GearItemEquipped(entry, slot) then return false end
    end
    return true
end

local function MaskIntersects(a, b)
    if bit and bit.band then return bit.band(a, b) ~= 0 end
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then return true end
        a, b = math.floor(a / 2), math.floor(b / 2)
    end
    return false
end

local function CompatibleFreeSlot(id)
    local free = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    local familyAPI = C_Item and C_Item.GetItemFamily or GetItemFamily
    local itemFamily
    if familyAPI then
        local ok, value = pcall(familyAPI, id)
        if ok and type(value) == "number" then itemFamily = value end
    end
    local unknownSpace
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local family
        if free then
            local ok, _, value = pcall(free, bag)
            if ok and type(value) == "number" then family = value end
        end
        -- The backpack is ordinary. Unknown specialty metadata is never
        -- evidence that it can receive displaced equipment.
        if bag == 0 or family == 0 or (family and family > 0 and itemFamily
            and itemFamily > 0 and MaskIntersects(family, itemFamily)) then
            for slot = 1, ContainerSlots(bag) do
                local itemID, _, _, _, locked = ContainerItem(bag, slot)
                if not itemID and not locked then return bag, slot end
            end
        elseif family == nil or (family > 0 and itemFamily == nil) then
            for slot = 1, ContainerSlots(bag) do
                local itemID = ContainerItem(bag, slot)
                if not itemID then unknownSpace = true; break end
            end
        end
    end
    return nil, nil, unknownSpace
end

local function SavedBagItem(entry, hint)
    -- Only an exact saved payload can bypass the full search. A stale, locked
    -- or changed position falls through so another matching copy may be used.
    if hint and entry.link and hint.link == entry.link then
        local id, _, link, _, locked = ContainerItem(hint.bag, hint.slot)
        if not locked and link == entry.link and SameGearItem(entry, id, link) then return link end
    end
    local lockedMatch, fallback
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, ContainerSlots(bag) do
            local id, _, link, _, locked = ContainerItem(bag, slot)
            if SameGearItem(entry, id, link) then
                if not locked then
                    -- Prefer the original full payload when it is still
                    -- available, before equivalent links with updated display
                    -- fields or otherwise indistinguishable native copies.
                    if link == entry.link then return link end
                    fallback = fallback or link or entry.link or entry.id
                else lockedMatch = true end
            end
        end
    end
    return fallback, not fallback and lockedMatch
end

function FF:CancelGearOperation()
    self.gearOperation = nil
    self.gearOpenEquipPending = nil
    self.pendingFishingGear, self.pendingGearRestore = nil, nil
    -- Equipment events from a cancelled/failed attempt cannot learn an
    -- intermediate weapon pair after its learning guard has gone away.
    self.normalWeaponCaptureToken = (self.normalWeaponCaptureToken or 0) + 1
    self.normalWeaponSetID = nil
end

function FF:BeginGearOperation(kind, target, scan)
    self.gearOperation = { kind = kind, target = target, db = self.db,
        owner = self:GearCharacterKey(), spec = CurrentGearSpecKey(self), waits = 0, issued = {} }
    if kind == "equip" then
        -- Copy only exact target locations from this explicit discovery pass.
        -- These unsaved hints belong to this operation, never to restoration.
        if scan then
            local hints = {}
            for _, item in ipairs(scan) do
                for slot, entry in pairs(target) do
                    if not hints[slot] and entry.link and entry.id == item.id and entry.link == item.link then
                        hints[slot] = { bag = item.bag, slot = item.slot, link = item.link }
                    end
                end
            end
            self.gearOperation.bagHints = hints
        end
        for slot, entry in pairs(target) do
            local original = self.db.gearRestore and self.db.gearRestore[slot]
            if original and GearItemEquipped(entry, slot) then
                original.fishingID, original.fishingLink = entry.id, entry.link
            end
        end
    end
    return self.gearOperation
end

local function RecordFishingOwnership(operation, action)
    if operation.kind ~= "equip" or action.entry.id == 0 then return end
    local original = operation.db.gearRestore and operation.db.gearRestore[action.slot]
    if original then
        original.fishingID = action.entry.id
        original.fishingLink = GetInventoryItemLink and GetInventoryItemLink("player", action.slot)
            or action.entry.link
    end
end

local function GearOperationCurrent(self, operation)
    return operation and self.gearOperation == operation and self.db == operation.db
        and self:GearCharacterKey() == operation.owner and CurrentGearSpecKey(self) == operation.spec
        and (operation.kind == "restore" and self.pendingGearRestore == operation.target
            or operation.kind == "equip" and self.pendingFishingGear)
end

local GEAR_FAILURE_HAS_RETRY = {
    ["gear.failure.unconfirmed"] = true,
    ["gear.failure.unknown-space"] = true,
    ["gear.failure.loading"] = true,
    ["gear.failure.context"] = true,
    ["gear.failure.combat"] = true,
    ["gear.failure.casting"] = true,
    ["gear.failure.cursor"] = true,
    ["gear.failure.locked"] = true,
    ["gear.failure.incomplete"] = true,
}
function FF:StopLocalizedGearOperation(operation, messageKey)
    return self:StopGearOperation(operation,self:LocalizedText(messageKey),GEAR_FAILURE_HAS_RETRY[messageKey])
end

function FF:StopGearOperation(operation, message, includesRetry)
    if not operation or self.gearOperation ~= operation then return end
    self:CancelGearOperation()
    self.gearSwapBlocked = { db = operation.db, spec = operation.spec }
    if message then
        self:ShowGearSwapFailure(message)
        -- Always show the current banner; identical rapid retries need only
        -- one chat explanation. This is transient, character/spec-owned state.
        local previous = self.gearChatFailure
        local now = GetTime()
        if not previous or previous.db ~= operation.db or previous.owner ~= operation.owner
            or previous.spec ~= operation.spec or previous.message ~= message
            or now - previous.at >= 5 or now < previous.at then
            self.gearChatFailure = { db = operation.db, owner = operation.owner,
                spec = operation.spec, message = message, at = now }
            local ended=message:match("[%.!?]$") or message:sub(-#"。") == "。"
                or message:sub(-#"！") == "！" or message:sub(-#"？") == "？"
            local punctuation = ended and "" or self:LocalizedText("format.sentence-end")
            self:Print(self:LocalizedText(includesRetry and "gear.failure-chat-recalled" or "gear.failure-chat-retry",message,punctuation))
        end
    end
    self:RefreshUI()
end

function FF:SuspendGearOperation()
    if not self.gearOperation then return end
    self.gearWorldInterrupted = true
    self:StopGearOperation(self.gearOperation)
end

function FF:OnGearEquipmentChanged(slot)
    local operation = self.gearOperation
    local action = operation and operation.action
    if not operation or (action and action.issuing) then return end
    -- The outstanding native hand action may also displace its paired hand.
    local nativeSlot = action and not action.confirmed and (slot == action.slot
        or ((action.slot == 16 or action.slot == 17) and (slot == 16 or slot == 17)
            and not GetInventoryItemID("player", slot)))
    local expected = operation.expected and operation.expected[slot]
    if not nativeSlot and expected and not GearItemEquipped(expected, slot) then
        -- Respect a new manual choice made after the native request settled.
        -- Cancellation retains the other original slots for a later restore.
        self:StopLocalizedGearOperation(operation, "gear.failure.manual-choice")
        self:QueueNormalWeaponCapture()
        return
    end
    -- Native equipment events can finish an asynchronous request without an
    -- extra polling delay. Invalidate its older scheduled continuation first.
    if action and GearItemEquipped(action.entry, action.slot) then
        operation.continuation = (operation.continuation or 0) + 1
        self:ContinueGearOperation(operation)
    end
end

local function NativeGearError(message, names, errorName)
    for _, name in ipairs(names) do
        if errorName == name then return true end
        local text = _G[name]
        if type(text) == "string" then
            if message == text then return true end
            -- Native subclass/level errors can contain localized %s/%d fields.
            -- Escape the rest of the native template, never match English.
            local pattern, fields = text:gsub("%%%d*%$?[sd]", "\001")
            if fields > 0 then
                pattern = pattern:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
                pattern = pattern:gsub("\001", ".+")
                if message:match("^" .. pattern .. "$") then return true end
            end
        end
    end
    return false
end

local GEAR_CAPACITY_ERRORS = { "ERR_INV_FULL", "ERR_BAG_FULL", "ERR_INVENTORY_FULL" }
local GEAR_BAG_ERRORS = { "ERR_WRONG_BAG_TYPE", "ERR_WRONG_BAG_TYPE_SUBCLASS", "ERR_AMMO_ONLY", "ERR_QUIVER_ONLY",
    "ERR_ONLY_AMMO_CAN_GO_HERE", "ERR_ITEM_DOESNT_GO_INTO_BAG" }
local GEAR_RESTRICTION_ERRORS = { "ERR_CANT_EQUIP_EVER", "ERR_CANT_EQUIP_SKILL",
    "ERR_CANT_EQUIP_LEVEL_I", "ERR_ITEM_MAX_COUNT_EQUIPPED", "ERR_NOT_EQUIPPABLE" }

function FF:OnGearSwapUIError(message, errorID)
    local operation = self.gearOperation
    local action = operation and operation.action
    -- Only a still-unsettled native request owns gear errors. Capacity errors
    -- may arrive after the short synchronous window, within its bounded wait.
    if not action or not GearOperationCurrent(self, operation) then return false end
    if type(message) ~= "string" then return false end
    if not action.issuing and GearItemEquipped(action.entry, action.slot) then return false end
    local errorName
    if GetGameMessageInfo and type(errorID) == "number" and errorID > 0
        and errorID == math.floor(errorID) and errorID < math.huge then
        local ok, name = pcall(GetGameMessageInfo, errorID)
        if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then errorName = name end
    end
    local capacity = NativeGearError(message, GEAR_CAPACITY_ERRORS, errorName)
    if not action.issuing and GetTime() > action.errorUntil and not capacity then return false end
    if capacity then
        self:StopLocalizedGearOperation(operation, "gear.failure.bags-full")
    elseif NativeGearError(message, GEAR_BAG_ERRORS, errorName) then
        -- Wrong bag type is not proof that every compatible bag is full.
        -- Let the actual capacity error own the stronger bags-full message.
        self:StopLocalizedGearOperation(operation, "gear.failure.bag-space")
    elseif NativeGearError(message, GEAR_RESTRICTION_ERRORS, errorName) then
        self:StopLocalizedGearOperation(operation, "gear.failure.requirements")
    else return false end
    return true
end

local function ScheduleGearOperation(self, operation)
    if self.gearOperation ~= operation then return end
    operation.continuation = (operation.continuation or 0) + 1
    local continuation = operation.continuation
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function()
            if self.gearOperation == operation and operation.continuation == continuation then
                self:ContinueGearOperation(operation)
            end
        end)
    else
        -- No timer means no deferred retries; settle a synchronous success.
        if operation.action and not GearItemEquipped(operation.action.entry, operation.action.slot) then
            self:StopLocalizedGearOperation(operation, "gear.failure.unconfirmed")
        else self:ContinueGearOperation(operation) end
    end
end

local function UnequipToBag(self, operation, slot)
    if not PickupInventoryItem or not CursorHasItem or not GetInventoryItemID then return false end
    if CursorHasItem() then return false end
    local pickupBag = C_Container and C_Container.PickupContainerItem or PickupContainerItem
    if not pickupBag then return false end
    -- Only genuinely empty original slots need an explicit bag destination.
    -- Positive equips always go directly to native equip, with no space veto.
    local bag, bagSlot, unknownSpace = CompatibleFreeSlot(GetInventoryItemID("player", slot))
    if bag == nil then
        self:StopLocalizedGearOperation(operation, unknownSpace and "gear.failure.unknown-space"
            or "gear.failure.bags-full")
        return false
    end
    if not GearOperationCurrent(self, operation) or (InCombatLockdown and InCombatLockdown()) then return false end
    local ok = pcall(PickupInventoryItem, slot)
    local submitted = false
    if ok and CursorHasItem() and GearOperationCurrent(self, operation)
        and not (InCombatLockdown and InCombatLockdown()) then
        ok = pcall(pickupBag, bag, bagSlot)
        submitted = ok and not CursorHasItem()
    end
    -- We started with a free cursor and only cancel the transfer we issued.
    if CursorHasItem() and ClearCursor then pcall(ClearCursor) end
    -- Bag placement and equipment reads need not settle together. A submitted
    -- transfer uses the same bounded confirmation as positive equips; a refused
    -- pickup/placement still fails, even if ClearCursor returned the item.
    return submitted
end

function FF:FinishGearRestore(operation)
    if operation and (not GearOperationCurrent(self, operation)
        or not SnapshotEquipped(operation.target)) then return end
    local noMelee = operation and operation.kind == "restore"
        and operation.target[16] and operation.target[16].id == 0
        and operation.target[17] and operation.target[17].id == 0
    local opened = self.gearOpenEquipPending
    self:CancelGearOperation()
    self.gearSwapBlocked = nil
    self.db.gearRestore = nil
    self.db.gearSwapActive = nil
    self.db.gearSwapSpec = nil
    self.db.gearSwapOwner = nil
    if type(self.db.gearRestoresByCharacter) == "table" then
        self.db.gearRestoresByCharacter[self:GearCharacterKey()] = nil
    end
    self.combatWeaponRestore = nil
    self.db.combatWeaponRestore = nil
    self.combatWeaponPlanDirty = true
    self:RememberNormalWeapons()
    if self.SyncSessionRodTime then self:SyncSessionRodTime() end
    self:RefreshUI()
    self:QueueNormalWeaponCapture()
    -- Both slots must be explicitly remembered empty and fully confirmed.
    -- This shared banner also remains visible after Auto Restore closes the bar.
    if noMelee and self.ShowPreparationStatusNotice then
        self:ShowPreparationStatusNotice(FF:LocalizedText("gear.no-melee"), "gearRestore")
    end
    -- The player may reopen while an asynchronous close restore is settling.
    -- Finish that issued request before preparing the newly requested outfit.
    -- Closing/context/selection cancellation discards this unsaved intent.
    if opened and opened.db == self.db and opened.owner == self:GearCharacterKey()
        and opened.spec == CurrentGearSpecKey(self) and self.bar and self.bar:IsShown()
        and self.db.autoEquipGear and not (InCombatLockdown and InCombatLockdown()) then
        local scan = self:ScanFishingInventory()
        self:EquipConfiguredFishingGear(true, scan)
    end
end

function FF:EquipFishingGearOnOpen(scan)
    if self.pendingGearRestore then
        self.gearOpenEquipPending = { db = self.db, owner = self:GearCharacterKey(),
            spec = CurrentGearSpecKey(self) }
        return
    end
    -- Opening is an explicit player retry. Automatic cast preparation still
    -- cannot replay a failed request while the same bar remains open.
    self.gearSwapBlocked = nil
    self:EquipConfiguredFishingGear(true, scan)
end

function FF:ContinueGearOperation(operation)
    if not operation or self.gearOperation ~= operation then return end
    if self.gearWorldInterrupted then
        self:StopLocalizedGearOperation(operation, "gear.failure.loading")
        return
    end
    if not GearOperationCurrent(self, operation) then
        self:StopLocalizedGearOperation(operation, "gear.failure.context")
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        self:StopLocalizedGearOperation(operation, "gear.failure.combat")
        return
    end
    if UnitCastingInfo and UnitCastingInfo("player") then
        self:StopLocalizedGearOperation(operation, "gear.failure.casting")
        return
    end
    if CursorHasItem and CursorHasItem() then
        self:StopLocalizedGearOperation(operation, "gear.failure.cursor")
        return
    end
    for _, entry in pairs(operation.target) do
        if type(entry) ~= "table" or type(entry.id) ~= "number" or entry.id < 0
            or entry.id ~= math.floor(entry.id) then
            self:StopLocalizedGearOperation(operation, "gear.failure.invalid-entry")
            return
        end
    end
    local action = operation.action
    if action then
        if GearItemEquipped(action.entry, action.slot) then
            -- Synchronous success already recorded ownership before taking
            -- the expected snapshot. Delayed success records it here once.
            if not action.confirmed then RecordFishingOwnership(operation, action) end
            operation.action, operation.waits = nil, 0
        else
            -- A native call has already been issued. Give delayed equipment
            -- events time to settle, without repeating the rejected request.
            operation.waits = operation.waits + 1
            if operation.waits < 8 then ScheduleGearOperation(self, operation)
            else self:StopLocalizedGearOperation(operation, "gear.failure.unconfirmed") end
            return
        end
    end
    if SnapshotEquipped(operation.target) then
        if operation.kind == "restore" then self:FinishGearRestore(operation)
        else
            self:CancelGearOperation()
            self.gearSwapBlocked = nil
            self:NotifyAvailableFishingGear()
            self:RefreshUI()
        end
        return
    end
    -- Positive equips can vacate a bag slot or displace the pole themselves.
    -- Do these before empty-slot cleanup; full bags still allow legal swaps.
    for pass = 1, 2 do
        for index = 1, 19 do
            -- Attempt the rod/main hand before any fishing armour. A native
            -- rejection stops this outfit before the remaining slots change.
            local slot = index
            if operation.kind == "equip" then
                slot = index == 1 and 16 or (index <= 16 and index - 1 or index)
            end
            local entry = operation.target[slot]
            if entry and (pass == 1 and entry.id > 0 or pass == 2 and entry.id == 0)
                and not GearItemEquipped(entry, slot) then
                if operation.issued[slot] then
                    -- A later equip displaced an earlier target: this outfit
                    -- cannot settle. Never oscillate between incompatible hands.
                    self:StopLocalizedGearOperation(operation, "gear.failure.incompatible")
                    return
                end
                local item, locked
                if entry.id > 0 then
                    item, locked = SavedBagItem(entry, operation.bagHints and operation.bagHints[slot])
                    if not item and not locked then
                        self:StopLocalizedGearOperation(operation, "gear.failure.item-missing")
                        return
                    end
                end
                if locked then
                    operation.waits = operation.waits + 1
                    if operation.waits < 8 then ScheduleGearOperation(self, operation)
                    else self:StopLocalizedGearOperation(operation, "gear.failure.locked") end
                    return
                end
                -- Optional inventory APIs may dispatch callbacks while read.
                -- Revalidate after lookup, immediately before any native action.
                if not GearOperationCurrent(self, operation) or (InCombatLockdown and InCombatLockdown()) then
                    self:StopLocalizedGearOperation(operation, "gear.failure.context")
                    return
                end
                operation.waits = 0
                -- Arm BEFORE the call: native errors/equipment events may
                -- arrive synchronously inside it. One request at a time.
                action = { entry = entry, slot = slot, issuing = true }
                operation.action = action
                action.errorUntil = GetTime() + 0.25
                operation.issued[slot] = true
                local ok
                if action.entry.id == 0 then ok = UnequipToBag(self, operation, action.slot)
                else
                    local equip = C_Item and C_Item.EquipItemByName or EquipItemByName
                    if equip then ok = pcall(equip, item, slot) end
                end
                action.issuing = nil
                if self.gearOperation ~= operation then return end
                if not ok then
                    self:StopLocalizedGearOperation(operation, "gear.failure.incomplete")
                    return
                end
                action.confirmed = GearItemEquipped(action.entry, action.slot)
                if action.confirmed then
                    RecordFishingOwnership(operation, action)
                    local slots = { [16] = true, [17] = true }
                    for targetSlot in pairs(operation.target) do slots[targetSlot] = true end
                    operation.expected = CaptureSlots(slots)
                    -- Successful native swaps need no artificial per-item
                    -- pause. At most one request per target slot is allowed,
                    -- so immediate continuation remains finite and serialized.
                    self:ContinueGearOperation(operation)
                else
                    ScheduleGearOperation(self, operation)
                end
                return
            end
        end
    end
end

function FF:ContinueGearRestore(operation)
    return self:ContinueGearOperation(operation or self.gearOperation)
end

function FF:RestoreRememberedGear()
    if InCombatLockdown and InCombatLockdown() then
        self:Print(FF:LocalizedText("gear.restore-combat-help"))
        return
    end
    if self.pendingGearRestore then return end
    self:CancelGearOperation()
    self.gearSwapBlocked = nil
    if not self:ResumeCombatGearSnapshot() then return end
    if self.db.gearSwapOwner and self.db.gearSwapOwner ~= self:GearCharacterKey() then
        self:Print(FF:LocalizedText("gear.restore-foreign-owner"))
        return
    end
    if type(self.db.gearRestore) == "table" and next(self.db.gearRestore) then
        local snapshot = {}
        for slot, entry in pairs(self.db.gearRestore) do
            -- A deliberate manual armour/ranged choice supersedes only that
            -- slot. Old public snapshots without ownership metadata still work.
            local fishing = entry.fishingID and { id = entry.fishingID, link = entry.fishingLink }
            if slot == 16 or slot == 17 or not fishing or GearItemEquipped(entry, slot)
                or GearItemEquipped(fishing, slot) then snapshot[slot] = entry end
        end
        local specKey = CurrentGearSpecKey(self)
        -- An explicit empty slot is a captured state, not an unknown weapon.
        -- Validate actual item types: an ordinary configured shield/weapon is
        -- not a pole. Unknown items and changed specs retain their guards.
        local fishingSnapshot = (snapshot[16] and snapshot[16].id ~= 0
            and not IsConfirmedWeaponItem(snapshot[16].id))
            or (snapshot[17] and IsFishingRodItem(self, snapshot[17].id))
        local changedSpec = self.db.gearSwapSpec and self.db.gearSwapSpec ~= specKey
        if (fishingSnapshot or changedSpec) and (snapshot[16] or snapshot[17]) then
            local weapons = ResolveNormalWeapons(self, specKey)
            if not weapons then
                WarnUnknownNormalWeapons(self)
                return
            end
            snapshot[16], snapshot[17] = weapons[16], weapons[17]
        end
        self.pendingGearRestore = snapshot
        self:BeginGearOperation("restore", snapshot)
        self:ContinueGearRestore()
    else
        self.db.gearSwapActive = nil
        self.db.gearSwapSpec = nil
        self.db.gearSwapOwner = nil
        if FishingWeaponEquipped(self) and not ResolveNormalWeapons(self, CurrentGearSpecKey(self)) then
            WarnUnknownNormalWeapons(self)
        else
            self:Print(FF:LocalizedText("gear.restore-missing"))
        end
        self:RefreshUI()
    end
end

function FF:RememberWornFishingGear(quiet)
    if self.combatWeaponRestore then return false end
    if self.db.gearSwapActive then return true end
    if not GetInventoryItemID or not IsFishingWeapon(self, 16, GetInventoryItemID("player", 16)) then return false end
    local specKey = CurrentGearSpecKey(self)
    local weapons = ResolveNormalWeapons(self, specKey)
    if not weapons then
        if not quiet then WarnUnknownNormalWeapons(self) end
        return false
    end
    local slots = { [16] = true, [17] = true }
    for slot in pairs(self.db.gearItems or {}) do slots[slot] = true end
    local snapshot = CaptureSlots(slots)
    snapshot[16], snapshot[17] = weapons[16], weapons[17] or { id = 0 }
    self.db.gearRestore = snapshot
    self.db.gearSwapActive = true
    self.db.gearSwapSpec = specKey
    self.db.gearSwapOwner = self:GearCharacterKey()
    return true
end

function FF:ContinueCustomGearEquip(operation)
    return self:ContinueGearOperation(operation or self.gearOperation)
end

function FF:EquipConfiguredFishingGear(automatic, scan)
    if InCombatLockdown and InCombatLockdown() then return end
    if self.pendingFishingGear or self.pendingGearRestore then return end
    if automatic and self.gearSwapBlocked and self.gearSwapBlocked.db == self.db
        and self.gearSwapBlocked.spec == CurrentGearSpecKey(self) then return end
    self.gearSwapBlocked = nil
    if CursorHasItem and CursorHasItem() then
        self:ShowGearSwapFailure(FF:LocalizedText("gear.failure.cursor"))
        self.gearSwapBlocked = { db = self.db, spec = CurrentGearSpecKey(self) }
        return
    end
    if not self:ResumeCombatGearSnapshot() then return end
    local gear = self:GetAvailableFishingGear()
    if not next(gear) or self:AvailableFishingGearEquipped() then self:NotifyAvailableFishingGear(); return end
    if self.db.gearSwapActive then
        -- Manual weapons may have superseded only the weapon part of an
        -- armour transaction. Capture newly replaced slots without overwriting
        -- any outstanding original armour or remembered manual weapon choice.
        self.db.gearRestore = self.db.gearRestore or {}
        local slots = {}
        for slot in pairs(self.db.gearItems or {}) do
            if not self.db.gearRestore[slot] then slots[slot] = true end
        end
        if self.db.gearItems[16] and not self.db.gearRestore[17] then slots[17] = true end
        local added = CaptureSlots(slots)
        if added[16] and IsFishingRodItem(self, added[16].id) then
            local weapons = ResolveNormalWeapons(self, CurrentGearSpecKey(self))
            if weapons then added[16], added[17] = weapons[16], weapons[17] end
        end
        for slot, entry in pairs(added) do self.db.gearRestore[slot] = entry end
        self.pendingFishingGear = true
        self:BeginGearOperation("equip", gear, scan)
        self:ContinueCustomGearEquip()
    elseif FishingWeaponEquipped(self) then
        local weapons = ResolveNormalWeapons(self, CurrentGearSpecKey(self))
        if not weapons and not automatic then
            WarnUnknownNormalWeapons(self)
            return
        end
        local slots = { [16] = true, [17] = true }
        for slot in pairs(self.db.gearItems) do slots[slot] = true end
        self.db.gearRestore = CaptureSlots(slots)
        if weapons then
            self.db.gearRestore[16], self.db.gearRestore[17] = weapons[16], weapons[17]
        end
        -- If normal weapons are unknown, an existing rod remains a fishing
        -- snapshot. RestoreRememberedGear resolves real weapons or prompts.
        self.db.gearSwapActive = true
        self.db.gearSwapSpec = CurrentGearSpecKey(self)
        self.db.gearSwapOwner = self:GearCharacterKey()
        self.pendingFishingGear = true
        self:BeginGearOperation("equip", gear, scan)
        self:ContinueCustomGearEquip()
    else
        self:RememberNormalWeapons()
        local slots = {}
        for slot in pairs(self.db.gearItems) do slots[slot] = true end
        -- A missing preferred pole may return during this same swap. Preserve
        -- the offhand now, even if only armour is available on the first click.
        if self.db.gearItems[16] then slots[17] = true end
        self.db.gearRestore = CaptureSlots(slots)
        self.db.gearSwapActive = true
        self.db.gearSwapSpec = CurrentGearSpecKey(self)
        self.db.gearSwapOwner = self:GearCharacterKey()
        self.pendingFishingGear = true
        self:BeginGearOperation("equip", gear, scan)
        self:ContinueCustomGearEquip()
    end
    -- Completion/failure already refreshed. Pending preparation needs an
    -- immediate readiness/binding update, not an unowned delayed full redraw.
    if self.gearOperation then self:RefreshUI(true) end
end

function FF:ToggleCustomGear()
    if InCombatLockdown and InCombatLockdown() then self:Print(FF:LocalizedText("gear.equip-combat")); return end
    if self.combatWeaponRestore then self:RestoreRememberedGear(); return end
    if self.pendingFishingGear or self.pendingGearRestore then return end
    if self.db.gearSwapActive and type(self.db.gearRestore) == "table" and next(self.db.gearRestore)
        and (not self.db.gearSwapOwner or self.db.gearSwapOwner == self:GearCharacterKey()) then
        -- Restoring known originals uses live action-time item/lock checks;
        -- discovery of fishing choices/lures is unnecessary for this branch.
        self.gearSwapBlocked = nil
        self:RestoreRememberedGear()
        return
    end
    local scan = self:ScanFishingInventory()
    self.gearSwapBlocked = nil
    if self.db.gearSwapActive then self:RestoreRememberedGear()
    elseif not next(self.db.gearItems or {}) then self:Print(FF:LocalizedText("gear.choose-arrow")); return
    elseif self:AvailableFishingGearEquipped() and FishingWeaponEquipped(self) then
        if self:RememberWornFishingGear() then self:RestoreRememberedGear() end
    else self:EquipConfiguredFishingGear(nil, scan) end
end

function FF:HandleGearClick(button, mouseButton)
    if InCombatLockdown and InCombatLockdown() then
        if mouseButton == "LeftButton" then self:BeginCombatWeaponRestore(button)
        else self:Print(FF:LocalizedText("gear.manage-combat")) end
        return
    end
    if mouseButton ~= "LeftButton" then return end
    self:ToggleCustomGear()
end

function FF:ShowGearPicker()
    if InCombatLockdown and InCombatLockdown() then
        self:Print(FF:LocalizedText("gear.manage-combat"))
        return
    end
    if self.IsCameraSearchPending and self:IsCameraSearchPending() then return end
    if self.utilityPicker then self.utilityPicker:Hide() end
    self:EnsureFishingBarExpanded()
    if self.gearPicker and self.gearPicker:IsShown() then
        self.gearPicker:Hide()
        return
    end
    if self.CloseFishingQuickTray then self:CloseFishingQuickTray() end
    if not self.gearPicker then
        self.gearPicker = CreatePicker("ForeverFishingGearPicker", "gear")
        self:BindFishingFlyoutOwner(self.gearPicker)
    end
    self:ScanFishingGear()
    self:RefreshGearPicker()
    if self.lurePicker then self.lurePicker:Hide() end
    self:RefreshFishingLayer()
    self:PositionFishingPicker(self.gearPicker, self.gearButton)
    self.gearPicker:Show()
end

local REMOVE_GEAR_POPUP = "FOREVER_FISHING_REMOVE_GEAR"
function FF:ConfirmRemoveFishingGearItem(slot)
    if InCombatLockdown and InCombatLockdown() then
        self:Print(FF:LocalizedText("gear.change-combat"))
        return
    end
    local item = self.db.gearItems[slot]
    if not item then return end
    if not StaticPopupDialogs or not StaticPopup_Show then
        self:Print(FF:LocalizedText("gear.confirmation-unavailable"))
        return
    end
    if not StaticPopupDialogs[REMOVE_GEAR_POPUP] then
        StaticPopupDialogs[REMOVE_GEAR_POPUP] = {
            text = FF:LocalizedText("gear.remove-confirm"),
            button1 = FF:LocalizedText("gear.remove"),
            button2 = CANCEL or FF:LocalizedText("binding.cancel"),
            OnAccept = function(dialog)
                local data = dialog.data
                local current = data and FF.db.gearItems[data.slot]
                if current and current.id == data.id then FF:RemoveFishingGearItem(data.slot) end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end
    local dialog = StaticPopup_Show(REMOVE_GEAR_POPUP, FriendlyItemName(item.id, item.link, item.name))
    if dialog then dialog.data = { slot = slot, id = item.id } end
end

function FF:RefreshGearPicker()
    if InCombatLockdown and InCombatLockdown() then return end
    local panel = self.gearPicker
    if not panel then return end
    if not panel.flyoutGeometryLocked then
        for _, row in ipairs(panel.rows) do row:Hide() end
    end
    local entries, selected = {}, {}
    for slot, item in pairs(self.db.gearItems or {}) do
        entries[#entries + 1] = { slot = slot, item = item, configured = true }
        selected[tostring(slot) .. ":" .. tostring(item.id)] = true
    end
    local bestBonus, ignored = {}, self.db.gearIgnored or {}
    for _, item in ipairs(self.availableFishingGear or {}) do
        if not ignored[item.id] and item.baseFishingBonus ~= nil then
            bestBonus[item.slot] = math.max(bestBonus[item.slot] or 0, item.baseFishingBonus)
        end
    end
    for _, item in ipairs(self.availableFishingGear or {}) do
        if not ignored[item.id] and not selected[tostring(item.slot) .. ":" .. tostring(item.id)]
            and (item.baseFishingBonus == nil or not bestBonus[item.slot] or item.baseFishingBonus >= bestBonus[item.slot]) then
            entries[#entries + 1] = { slot = item.slot, item = item }
        end
    end
    table.sort(entries, function(a, b)
        if a.slot ~= b.slot then return a.slot < b.slot end
        if a.configured ~= b.configured then return a.configured == true end
        if (a.item.score or 0) ~= (b.item.score or 0) then
            return (a.item.score or 0) > (b.item.score or 0)
        end
        return (a.item.name or "") < (b.item.name or "")
    end)
    entries[#entries + 1] = { add = true }
    entries = self:ResolveFishingFlyoutEntries(panel,entries)
    for index, entry in ipairs(entries) do
        local gearEntry = entry
        local row = PickerRow(panel, index)
        if not panel.flyoutGeometryLocked then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel.content, "TOPLEFT",
                ((index - 1) % panel.flyoutColumns) * panel.flyoutStep,
                -math.floor((index - 1) / panel.flyoutColumns) * panel.flyoutStep)
        end
        row:SetIcon(entry.item and (entry.item.icon or DEFAULT_GEAR_ICON) or nil,
            entry.configured == true)
        row.itemID = entry.item and entry.item.id or nil
        row.itemLink = entry.item and entry.item.link or nil
        row.itemBag = nil
        row.itemBagSlot = nil
        row.itemEquipSlot = entry.item and entry.slot or nil
        row.tooltipTitle = entry.item and FriendlyItemName(entry.item.id, entry.item.link, entry.item.name) or FF:LocalizedText("gear.add")
        row.tooltipLine = entry.item and FF:LocalizedText(entry.configured and "gear.picker-remove" or "gear.picker-select",GearSlotLabel(entry.slot,true))
            or FF:LocalizedText("gear.drop")
        if entry.add then
            local function AddDroppedGear()
                local kind, id, link = GetCursorInfo()
                if kind == "item" and tonumber(id) and self:AddFishingGearItem(tonumber(id), link) then
                    ClearCursor()
                    self:RefreshGearPicker()
                end
            end
            row:SetScript("OnClick", function(_, button)
                if button == "LeftButton" then AddDroppedGear() end
            end)
            row:SetScript("OnReceiveDrag", AddDroppedGear)
        else
            row:SetScript("OnReceiveDrag", nil)
            row:SetScript("OnClick", function(_, mouseButton)
                if mouseButton == "LeftButton" then
                    if gearEntry.configured then
                        self:FinishFishingFlyoutSelection(panel)
                        self:ToggleCustomGear()
                    elseif self:AddFishingGearItem(gearEntry.item.id, gearEntry.item.link, gearEntry.slot) then
                        self:FinishFishingFlyoutSelection(panel)
                    end
                elseif mouseButton == "RightButton" and gearEntry.configured then
                    self:ConfirmRemoveFishingGearItem(gearEntry.slot)
                end
            end)
        end
        row:SetEnabled(not entry.flyoutUnavailable)
        row:SetAlpha(entry.flyoutUnavailable and .35 or 1)
        row:Show()
    end
    panel.flyoutFixedButton = panel.rows[#entries]
    if not panel.flyoutGeometryLocked then panel:SizeForRows(#entries) end
    if panel:IsShown() then self:PositionFishingPicker(panel, self.gearButton) end
end

function FF:RefreshSmartButtons()
    if not self.gearButton or not self.lureButton then return end
    self:SyncCombatWeaponRestore()
    self:SyncLureButton()

    local hasGear, gearEquipped = false, false
    if next(self:GetAvailableFishingGear()) then
        hasGear = true
        gearEquipped = self:AvailableFishingGearEquipped()
    end
    self.gearButton.icon:SetTexture((self.fishingRodEquipped or self.fishingRodInBags)
        and self.fishingGearIcon or self.fishingGearPurchaseIcon)
    local gearGlow = hasGear and not gearEquipped
    self:SetSmartGlow(self.gearButton, gearGlow)

    local lureID = self.db.lure
    local lureName, _, _, _, lureIcon = ItemInfo(lureID)
    local hasLures = self.availableLures and self.availableLures[1]
    self.lureButton.icon:SetTexture(hasLures and (lureIcon or DEFAULT_LURE_ICON) or self.lurePurchaseIcon)
    self.lureButton.icon:SetTexCoord(hasLures and 0.07 or 0, hasLures and 0.93 or 1,
        hasLures and 0.07 or 0, hasLures and 0.93 or 1)
    local remaining = self:LureSeconds()
    local lureGlow = remaining ~= nil and remaining <= 0
    local selectedAvailable = false
    for _, entry in ipairs(self.availableLures or {}) do
        if entry.id == lureID then selectedAvailable = true; break end
    end
    local manualReplacementNeeded = self.db.lureManual and lureID and not selectedAvailable
    if manualReplacementNeeded then lureGlow = true end
    -- Empty-stock suppression also applies to a remembered manual choice.
    -- Keep that choice for restocking; it must not override this preference.
    if self.db.hideLureGlowWhenOutOfLures and not hasLures then lureGlow = false end
    self:SetSmartGlow(self.lureButton, lureGlow)
    local selectedLink
    for _, entry in ipairs(self.availableLures or {}) do
        if entry.id == lureID then selectedLink = entry.link; break end
    end
    self.lureButton.selectedName = not hasLures and FF:LocalizedText("lure.no-bags")
        or (lureID and FriendlyItemName(lureID, selectedLink, lureName) or FF:LocalizedText("lure.name"))
    if self.RefreshFishingBarAttention then self:RefreshFishingBarAttention(gearGlow, lureGlow) end
end
