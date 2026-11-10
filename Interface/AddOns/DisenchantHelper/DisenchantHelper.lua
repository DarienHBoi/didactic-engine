local ADDON_NAME, ns = ...
local addon = CreateFrame("Frame")

local SPELL_ID_DISENCHANT = 13262
local BACKPACK_BAG = (Enum and Enum.BagIndex and Enum.BagIndex.Backpack) or 0
local REAGENT_BAG = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag  -- nil on Classic

-- Bags to scan: backpack + equipped bags, plus the reagent bag on Retail only.
-- Classic has no reagent bag (slot 5 there can be a bank bag), so it is omitted.
local BAGS_TO_SCAN = {}
for bag = BACKPACK_BAG, BACKPACK_BAG + (NUM_BAG_SLOTS or 4) do
    BAGS_TO_SCAN[#BAGS_TO_SCAN + 1] = bag
end
if REAGENT_BAG then
    BAGS_TO_SCAN[#BAGS_TO_SCAN + 1] = REAGENT_BAG
end
local UNCOMMON_QUALITY = (Enum and Enum.ItemQuality and Enum.ItemQuality.Uncommon) or 2
local EPIC_QUALITY = (Enum and Enum.ItemQuality and Enum.ItemQuality.Epic) or 4
local RARE_QUALITY = (Enum and Enum.ItemQuality and Enum.ItemQuality.Rare) or 3

local BIND_ON_ACQUIRE = (Enum and Enum.ItemBind and Enum.ItemBind.OnAcquire) or 1
local BIND_ON_EQUIP = (Enum and Enum.ItemBind and Enum.ItemBind.OnEquip) or 2
local BIND_ACCOUNT = (Enum and Enum.ItemBind and Enum.ItemBind.ToWoWAccount) or 7
local BIND_BNET = (Enum and Enum.ItemBind and Enum.ItemBind.ToBnetAccount) or 8
local BIND_BNET_UNTIL_EQUIP = (Enum and Enum.ItemBind and Enum.ItemBind.ToBnetAccountUntilEquipped) or 9

local ROW_HEIGHT = 30
local ROW_SPACING = 4
local QUEUE_PANEL_WIDTH = 320

-- Shared locale table: guarantee it exists and capture the SAME table
-- Locales.lua fills, so this stays valid no matter which file loads first.
ns.L = ns.L or {}
local L = ns.L

-- Key binding support (1.7.0). The queue button needs a GLOBAL NAME so the
-- client's own binding system can target it via a "CLICK <name>:<button>"
-- binding (declared in Bindings.xml, so it also shows up under
-- Options > Key Bindings > Disenchant Helper). One key press = one click on this button =
-- one cast, exactly like a mouse click: all existing safety (debounce, stale
-- target check, click-edge matching) applies unchanged.
local QUEUE_BUTTON_NAME = "DisenchantHelper_QueueButton"
local QUEUE_BINDING = "CLICK " .. QUEUE_BUTTON_NAME .. ":LeftButton"
-- HEADER names the section, CATEGORY gives the addon its own entry in the
-- client's Key Bindings list instead of the generic "AddOns" group.
-- The client resolves the category name from a global; which exact name it
-- looks up differs between client generations, so all three spellings are set.
_G["BINDING_HEADER_DISENCHANTHELPER"] = "Disenchant Helper"
_G["BINDING_CATEGORY_DISENCHANTHELPER"] = "Disenchant Helper"
_G["DISENCHANTHELPER"] = "Disenchant Helper"
-- The label follows the active mode ("Disenchant next item", "Mill next
-- item", ...). Called at load and whenever the mode changes.
local function UpdateBindingName(modeButtonTextKey)
    local verb = L[modeButtonTextKey or "DISENCHANT"] or L["DISENCHANT"]
    _G["BINDING_NAME_" .. QUEUE_BINDING] = string.format(L["HOTKEY_BINDING_NAME"], verb)
end
UpdateBindingName()

local db
local items = {}
local selected = {}
local queue = {}
local needsRefreshAfterCombat = false
-- How many items the automatic compact queue skipped SOLELY because of the
-- price threshold (set in BuildQueue, read by the surface via the getter below).
local valuableSkippedCount = 0
-- The currently selected processing mode (1.6.0). Assigned once ns.Modes is
-- built further down and re-selected from the DB in ADDON_LOADED; used at
-- runtime only, so the forward declaration here is enough.
local activeMode

local mainFrame
local listPanel
local listScrollFrame
local listScrollChild
local queuePanel
local queueScrollFrame
local queueScrollChild
local statusText
local mainSubtitle
local modeTabFrame
local modeTabButtons = {}
local queueInfoText
local queueButton
local queueButtonText
local manualBlacklistButton
local blacklistOpenButton
local listRows = {}
local queueRows = {}
local blacklistRows = {}
local libDBIcon

local compactFrame
local compactPreviewText
local compactIcon
local compactNameText
local compactQueueText
local compactFullButton
local compactModeSelector
local compactModeMenu
local compactModeMenuButtons = {}
local settingsFrame
local settingsProtectionGroup
local settingsModeHint

local blacklistFrame
local blacklistScrollFrame
local blacklistScrollChild
local blacklistEmptyText

local RefreshUI
local RefreshList
local RefreshBlacklistUI
local ToggleBlacklistFrame
local AddPendingItemToBlacklist
local ValidatePendingItemForBlacklist
local UpdateCompactFrame
local SetCompactMode
local ToggleSettingsFrame
local UpdateModeSurface

local pendingLootUntil = 0
local pendingDisenchantUntil = 0
local pendingDisenchantItem
local pendingValidationToken = 0
local nextAllowedQueueClickAt = 0
local scanTooltip

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcDisenchant Helper:|r " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Shared visual building blocks
-- These tables/factories used to be copy-pasted at every call site; with one
-- definition, a look change is one edit instead of a hunt for n duplicates.
-- Sharing the backdrop TABLES across frames is safe - SetBackdrop only reads.
-- ---------------------------------------------------------------------------
local BACKDROP_WINDOW = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BACKDROP_PANEL = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
local BACKDROP_ICON = {
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    bgFile = "Interface\\Buttons\\WHITE8x8",
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- The framed item-icon square used by the list rows, queue rows, blacklist
-- rows and the compact bar (previously four identical inline blocks).
local function CreateIconBorder(parent, size)
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetSize(size, size)
    border:SetBackdrop(BACKDROP_ICON)
    border:SetBackdropColor(0, 0, 0, 1)
    border:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    return border
end

local function EnsureDB()
    DisenchantHelperDB = DisenchantHelperDB or {}
    db = DisenchantHelperDB
    if type(db.minimap) ~= "table" then
        db.minimap = {}
        -- Migrate angle & visibility from the old hand-built minimap button
        if db.minimapAngle ~= nil then
            db.minimap.minimapPos = db.minimapAngle
        end
        if db.hidden ~= nil then
            db.minimap.hide = db.hidden and true or false
        end
        db.minimapAngle = nil
        db.hidden = nil
    end
    -- Blacklist: migrate the pre-1.6 flat shape ({ [key] = true }) to the per-mode
    -- shape ({ disenchant = { [key] = true }, ... }). "Already migrated" is detected
    -- by a mode sub-table being present; otherwise every flat entry moves under
    -- "disenchant" (the only mode that existed before).
    if type(db.blacklist) ~= "table" then
        db.blacklist = {}
    end
    local blacklistMigrated = type(db.blacklist.disenchant) == "table"
        or type(db.blacklist.milling) == "table"
        or type(db.blacklist.prospecting) == "table"
    if not blacklistMigrated then
        local flat = {}
        for k, v in pairs(db.blacklist) do
            if v == true then
                flat[k] = true
            end
        end
        db.blacklist = { disenchant = flat }
    end
    if db.compactMode == nil then
        db.compactMode = false
    end
    if db.ilvlCapEnabled == nil then
        db.ilvlCapEnabled = false
    end
    if type(db.qualityFilter) ~= "table" then
        db.qualityFilter = {}
    end
    -- Shape guard like the others: a corrupted non-table value here would
    -- crash the compact bar's SetPoint on load. nil is fine (default center).
    if db.compactPoint ~= nil and type(db.compactPoint) ~= "table" then
        db.compactPoint = nil
    end
    -- Value guard (v1.5.0): default off. priceThresholdGold nil = "unset" -
    -- the guard stays inert until the user enters a number (same idea as the
    -- ilvl cap), so a corrupted non-number is coerced back to nil, not 0.
    if type(db.priceWarnEnabled) ~= "boolean" then
        db.priceWarnEnabled = false
    end
    if db.priceThresholdGold ~= nil and type(db.priceThresholdGold) ~= "number" then
        db.priceThresholdGold = nil
    end
    -- Active processing mode (1.6.0). An unknown or not-yet-existing key (e.g. a
    -- stored "milling" before that mode ships) resolves to disenchant at load,
    -- so this can never break startup.
    if type(db.activeMode) ~= "string" then
        db.activeMode = "disenchant"
    end
    if type(db.showExpected) ~= "boolean" then db.showExpected = true end
    if type(db.externalItemTooltips) ~= "boolean" then db.externalItemTooltips = false end
end

local function GetSpellNameSafe(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    if GetSpellInfo then
        return GetSpellInfo(spellID)
    end
end

local function GetSpellTextureSafe(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    if GetSpellTexture then
        return GetSpellTexture(spellID)
    end
end

local function GetItemInfoSafe(itemRef)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemRef)
    end
    if GetItemInfo then
        return GetItemInfo(itemRef)
    end
end

local function PlayerKnowsSpellID(spellID)
    if not spellID then
        return false
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(spellID)
    end
    if IsPlayerSpell then
        return IsPlayerSpell(spellID)
    end
    if IsSpellKnown then
        return IsSpellKnown(spellID)
    end
    return false
end

local function PlayerKnowsDisenchant()
    return PlayerKnowsSpellID(SPELL_ID_DISENCHANT)
end

-- ================= Material modes (1.6.0 Step 2) — FIRST CUT =================
-- Testable first cut. The spell IDs are stable/well-known; the pieces that still
-- need live Cata/MoP confirmation are the herb/ore DETECTION (item class/subclass)
-- and the failure strings. Detection is Enum-first (robust when the Enum table is
-- present) with numeric fallbacks; /deh check dumps sample trade-good class ids so
-- the numbers can be pinned down in-game. classifyFailure is deliberately inert for
-- materials in this cut, so nothing gets wrongly blacklisted during testing.
local SPELL_ID_MILLING     = 51005   -- Milling (Inscription)
local SPELL_ID_PROSPECTING = 31252   -- Prospecting (Jewelcrafting)

-- Milling/prospecting are Classic-only by product decision (Retail item structure
-- differs); offered only on a non-Retail client AND when the spell resolves.
-- Feature-detected: missing project globals -> false (mode simply not offered).
local IS_NON_RETAIL_CLIENT =
    (WOW_PROJECT_ID ~= nil and WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE)

local TRADEGOODS_CLASS      = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
-- VERIFY on Cata/MoP: Enum is tried first; these numbers are only the fallback.
local HERB_SUBCLASS         = (Enum and Enum.ItemTradegoodsSubclass and Enum.ItemTradegoodsSubclass.Herb) or 9
local METAL_STONE_SUBCLASS  = (Enum and Enum.ItemTradegoodsSubclass and Enum.ItemTradegoodsSubclass.MetalAndStone) or 7

local function GetItemClassIDs(itemLink)
    if not itemLink then
        return nil
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local itemID, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemLink)
        return classID, subclassID, itemID
    end
    if GetItemInfoInstant then
        local itemID, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemLink)
        return classID, subclassID, itemID
    end
    return nil
end

local function IsMillableHerb(itemLink)
    local classID, subclassID = GetItemClassIDs(itemLink)
    return classID == TRADEGOODS_CLASS and subclassID == HERB_SUBCLASS
end

-- "Metal & Stone" also contains bars and rough stones, so subclass alone is too
-- broad (live-confirmed on MoP). The supported TBC-through-MoP clients have a
-- finite, stable set of prospectable ores; item IDs keep detection independent of
-- the game locale and deliberately exclude precious/non-prospectable ores.
local PROSPECTABLE_ORE_IDS = {
    -- Classic/TBC
    [2770] = true,   -- Copper Ore
    [2771] = true,   -- Tin Ore
    [2772] = true,   -- Iron Ore
    [3858] = true,   -- Mithril Ore
    [10620] = true,  -- Thorium Ore
    [23424] = true,  -- Fel Iron Ore
    [23425] = true,  -- Adamantite Ore
    -- Wrath
    [36909] = true,  -- Cobalt Ore
    [36912] = true,  -- Saronite Ore
    [36910] = true,  -- Titanium Ore
    -- Cataclysm
    [53038] = true,  -- Obsidium Ore
    [52185] = true,  -- Elementium Ore
    [52183] = true,  -- Pyrite Ore
    -- Mists of Pandaria
    [72092] = true,  -- Ghost Iron Ore
    [72093] = true,  -- Kyparite
    [72094] = true,  -- Black Trillium Ore
    [72103] = true,  -- White Trillium Ore
}

local function IsProspectableOre(itemLink)
    local classID, subclassID, itemID = GetItemClassIDs(itemLink)
    return classID == TRADEGOODS_CLASS
        and subclassID == METAL_STONE_SUBCLASS
        and PROSPECTABLE_ORE_IDS[itemID] == true
end

local function StripColorCodes(text)
    if not text or text == "" then
        return ""
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    return text
end

local function GetDisplayName(itemName, itemLink)
    local cleanedName = StripColorCodes(itemName)
    if cleanedName ~= "" then
        return cleanedName
    end

    if type(itemLink) == "string" then
        local extracted = itemLink:match("%[(.-)%]")
        extracted = StripColorCodes(extracted)
        if extracted ~= "" then
            return extracted
        end
    end

    return L["UNKNOWN_ITEM"]
end

-- A stable key for the "selected" set. Prefer the item's GUID so a checkmark
-- follows the item even when bags reshuffle after a disenchant. Falls back to
-- bag:slot+itemID on clients without the GUID API (older Classic).
local function ComputeItemKey(bag, slot, itemLink)
    if C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if loc and C_Item.DoesItemExist and C_Item.DoesItemExist(loc) then
            local guid = C_Item.GetItemGUID(loc)
            if guid then
                return guid
            end
        end
    end
    local itemID = itemLink and itemLink:match("item:(%d+)")
    return tostring(bag) .. ":" .. tostring(slot) .. ":" .. tostring(itemID or "?")
end

local function GetItemIDFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end

    local itemID = itemLink:match("item:(%d+)")
    if itemID then
        return tonumber(itemID)
    end

    return nil
end

local function GetBlacklistKeyFromLink(itemLink)
    local itemID = GetItemIDFromLink(itemLink)
    if itemID then
        return tostring(itemID)
    end

    if type(itemLink) == "string" and itemLink ~= "" then
        local itemString = itemLink:match("|H(item:[^|]+)|h") or itemLink:match("(item:[^|]+)")
        if itemString and itemString ~= "" then
            return itemString
        end
    end

    return nil
end

-- Per-mode blacklist (1.6.0 Step 2b): an item that "cannot be milled" is not the
-- same as "cannot be disenchanted", so each mode keeps its own blacklist namespace
-- under db.blacklist[modeKey]. The lazy create keeps every caller simple.
local function GetModeBlacklist(modeKey)
    modeKey = modeKey or (activeMode and activeMode.key) or "disenchant"
    if type(db.blacklist) ~= "table" then
        db.blacklist = {}
    end
    if type(db.blacklist[modeKey]) ~= "table" then
        db.blacklist[modeKey] = {}
    end
    return db.blacklist[modeKey]
end

local function IsBlacklistedItem(itemLink)
    local blacklistKey = GetBlacklistKeyFromLink(itemLink)
    if blacklistKey == nil or not db then
        return false
    end
    return GetModeBlacklist()[blacklistKey] == true
end

local function ClearPendingDisenchant()
    pendingValidationToken = pendingValidationToken + 1
    pendingDisenchantUntil = 0
    pendingDisenchantItem = nil
end

local function SetPendingDisenchant(item)
    if not item then
        ClearPendingDisenchant()
        return
    end

    pendingValidationToken = pendingValidationToken + 1
    pendingDisenchantUntil = GetTime() + 8
    pendingDisenchantItem = {
        bag = item.bag,
        slot = item.slot,
        key = item.key,
        link = item.link,
        name = item.name or L["UNKNOWN"],
        itemID = GetItemIDFromLink(item.link),
    }
end

local function GetBagItemLinkSafe(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    end
    if GetContainerItemLink then
        return GetContainerItemLink(bag, slot)
    end
    return nil
end

local function DoesPendingItemStillExist(item)
    if not item then
        return false
    end

    local currentLink = GetBagItemLinkSafe(item.bag, item.slot)
    if currentLink and item.link and GetBlacklistKeyFromLink(currentLink) == GetBlacklistKeyFromLink(item.link) then
        return true
    end

    local wantedKey = item.link and GetBlacklistKeyFromLink(item.link) or nil
    if not wantedKey then
        return false
    end

    for _, bag in ipairs(BAGS_TO_SCAN) do
        local numSlots = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or 0
        for slot = 1, numSlots do
            local link = GetBagItemLinkSafe(bag, slot)
            if link and GetBlacklistKeyFromLink(link) == wantedKey then
                return true
            end
        end
    end

    return false
end


local function EnsureScanTooltip()
    if scanTooltip then
        return scanTooltip
    end

    scanTooltip = CreateFrame("GameTooltip", "DisenchantHelper_ScanTooltip", UIParent, "GameTooltipTemplate")
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTooltip
end

local function GetTooltipLinesForItem(item)
    local lines = {}

    if C_TooltipInfo and C_TooltipInfo.GetBagItem and item and item.bag ~= nil and item.slot ~= nil then
        local data = C_TooltipInfo.GetBagItem(item.bag, item.slot)
        if data and type(data.lines) == "table" then
            for _, lineData in ipairs(data.lines) do
                local leftText = lineData.leftText
                local rightText = lineData.rightText
                if type(leftText) == "string" and leftText ~= "" then
                    lines[#lines + 1] = leftText
                end
                if type(rightText) == "string" and rightText ~= "" then
                    lines[#lines + 1] = rightText
                end
                if type(lineData.text) == "string" and lineData.text ~= "" then
                    lines[#lines + 1] = lineData.text
                end
            end
        end
        if #lines > 0 then
            return lines
        end
    end

    local tooltip = EnsureScanTooltip()
    -- Re-own before EVERY scan: Hide() at the end of this function clears the
    -- owner, and an ownerless tooltip silently yields zero lines - which would
    -- kill the tooltip fallback from the second scan onward (only relevant on
    -- clients without C_TooltipInfo, i.e. older Classic flavors).
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:ClearLines()

    if item and item.bag ~= nil and item.slot ~= nil and tooltip.SetBagItem then
        tooltip:SetBagItem(item.bag, item.slot)
    elseif item and item.link and tooltip.SetHyperlink then
        tooltip:SetHyperlink(item.link)
    else
        return {}
    end

    for i = 1, tooltip:NumLines() or 0 do
        local left = _G["DisenchantHelper_ScanTooltipTextLeft" .. i]
        local textValue = left and left:GetText()
        if textValue and textValue ~= "" then
            lines[#lines + 1] = textValue
        end
    end
    tooltip:Hide()
    return lines
end

local function TooltipSaysCantDisenchant(item)
    if not item then
        return false
    end

    local cantBeDisenchanted = type(ERR_CANT_BE_DISENCHANTED) == "string" and string.lower(ERR_CANT_BE_DISENCHANTED) or nil

    for _, line in ipairs(GetTooltipLinesForItem(item)) do
        local cleaned = string.lower(StripColorCodes(line))
        if cantBeDisenchanted and cleaned == cantBeDisenchanted then
            return true
        end
        if cleaned:find("cannot be disenchanted", 1, true) or cleaned:find("can not be disenchanted", 1, true) then
            return true
        end
        if cleaned:find("nicht entzauberbar", 1, true) or cleaned:find("kann nicht entzaubert", 1, true) then
            return true
        end
    end

    return false
end

local function GetBindTagText(bindType, isBound)
    if bindType == BIND_BNET_UNTIL_EQUIP or bindType == BIND_ACCOUNT or bindType == BIND_BNET then
        return "|cff00ccffWB|r"
    end
    if bindType == BIND_ON_EQUIP and not isBound then
        return "|cff1eff00BoE|r"
    end
    if bindType == BIND_ON_ACQUIRE or isBound then
        return "|cff9d9d9dBoP|r"
    end
    return nil
end

-- Lowest equipped item level (slots 1-17, skipping shirt/slot 4):
-- anything below it cannot be an upgrade -> safe threshold suggestion
local function GetLowestEquippedItemLevel()
    local lowest
    for slot = 1, 17 do
        if slot ~= 4 then
            local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
            if link then
                local ilvl
                if C_Item and C_Item.GetDetailedItemLevelInfo then
                    ilvl = C_Item.GetDetailedItemLevelInfo(link)
                elseif GetDetailedItemLevelInfo then
                    ilvl = GetDetailedItemLevelInfo(link)
                end
                if ilvl and ilvl > 0 and (not lowest or ilvl < lowest) then
                    lowest = ilvl
                end
            end
        end
    end
    return lowest
end

local function IsQualityEnabled(quality)
    if not db or type(db.qualityFilter) ~= "table" then
        return true
    end
    return db.qualityFilter[quality] ~= false
end

local function IsForeverDisenchantMaterial(link)
    if not ns.EraReference or ns.EraReference.Client() ~= "forever" then return false end
    local id = GetItemIDFromLink(link)
    return id == 275724 or id == 247883 -- Hexed Pendant / Crude Wax Effigy
end

local function IsReasonablyDisenchantable(itemLink, itemQuality)
    if not itemLink or not itemQuality then
        return false
    end

    if itemQuality < UNCOMMON_QUALITY or itemQuality > EPIC_QUALITY then
        return false
    end

    if IsForeverDisenchantMaterial(itemLink) then return true end

    local equippable = (C_Item and C_Item.IsEquippableItem and C_Item.IsEquippableItem(itemLink))
        or (IsEquippableItem and IsEquippableItem(itemLink))
    if not equippable then
        return false
    end

    return true
end

local function SortItems()
    table.sort(items, function(a, b)
        if a.quality ~= b.quality then
            return a.quality > b.quality
        end
        if a.itemLevel ~= b.itemLevel then
            return a.itemLevel > b.itemLevel
        end
        return a.name < b.name
    end)
end

-- The three independent reasons an item is kept out of the AUTOMATIC compact
-- queue. Split into predicates (was one inline chain) so the "skipped solely
-- because of price" counter can ask each reason separately.
local function IsSetProtected(item)
    return item.isSet == true
end

local function IsIlvlProtected(item)
    if not (db and db.ilvlCapEnabled) then
        return false
    end
    local cap = tonumber(db.ilvlCap)
    return cap ~= nil and (item.itemLevel or 0) >= cap
end

-- Price protection: an item worth more than the user's gold threshold on the
-- AH should not be auto-shredded. Central comparison (Sol's interface note 1):
-- provider values are COPPER, the user enters whole GOLD -> * 10000 here, once.
-- A nil price means "unknown" (guard off / no price addon / no data), never 0.
local function IsValuableItem(item)
    if not (activeMode and activeMode.usesItemProtection) then
        return false
    end
    if not (db and db.priceWarnEnabled) then
        return false
    end
    local threshold = tonumber(db.priceThresholdGold)
    if not threshold then
        return false
    end
    return item.priceCopper ~= nil and item.priceCopper >= threshold * 10000
end

local function IsAutoQueueProtected(item)
    if not (activeMode and activeMode.usesItemProtection) then
        return false
    end
    return item.manualOnly or IsSetProtected(item) or IsIlvlProtected(item) or IsValuableItem(item)
end

local function BuildQueue()
    wipe(queue)
    valuableSkippedCount = 0
    for _, item in ipairs(items) do
        if selected[item.key] then
            queue[#queue + 1] = item
        end
    end

    -- Compact bar with no manual selection: queue every found item.
    -- Protected items (sets, ilvl cap, valuable) are SKIPPED here - they only
    -- enter the queue via a manual checkbox in the main window.
    if #queue == 0 and db and db.compactMode and compactFrame and compactFrame:IsShown() then
        for _, item in ipairs(items) do
            if IsAutoQueueProtected(item) then
                -- Count only those excluded PURELY by their value - a set or
                -- ilvl-capped item would have been skipped anyway, so it does
                -- not count as "skipped because it's valuable".
                if not item.manualOnly and IsValuableItem(item) and not IsSetProtected(item) and not IsIlvlProtected(item) then
                    valuableSkippedCount = valuableSkippedCount + 1
                end
            else
                queue[#queue + 1] = item
            end
        end
    end
end

-- Stable interface for the surface (compact-bar counter). Returns the number
-- of items the last auto-queue build skipped purely because of the price guard.
function ns.GetValuableSkippedCount()
    return valuableSkippedCount
end

local itemLoadRefreshQueued = false
-- Retry bookkeeping per bag slot: an item whose data NEVER loads (corrupt
-- cache entry, server hiccup) must not put the rescan loop on an endless
-- 4-per-second treadmill. After the cap, that slot is skipped until its
-- content changes; the counter resets as soon as the item loads normally.
local itemLoadRetries = {}
local MAX_ITEM_LOAD_RETRIES = 10

local function QueueRefreshWhenItemLoaded(bag, slot)
    if not (Item and Item.CreateFromBagAndSlot) then
        return
    end

    local itemObj = Item:CreateFromBagAndSlot(bag, slot)
    if not itemObj or itemObj:IsItemEmpty() then
        return
    end

    itemObj:ContinueOnItemLoad(function()
        if itemLoadRefreshQueued then
            return
        end

        if not (C_Timer and C_Timer.After) then
            return
        end

        itemLoadRefreshQueued = true
        C_Timer.After(0.25, function()
            itemLoadRefreshQueued = false
            -- Compact mode counts too: right after login the item cache is
            -- cold, and without this the bar showed a partial queue until some
            -- unrelated bag event happened to arrive.
            local anyShown = (mainFrame and mainFrame:IsShown())
                or (compactFrame and compactFrame:IsShown())
            if anyShown and RefreshList then
                RefreshList()
            end
        end)
    end)
end

-- Look up an item's AH value, but ONLY when the value guard is actually active
-- (Sol's interface note 2): no price-addon calls otherwise. Returns copper +
-- source label, or nil,nil when the guard is off / no price addon / no data.
-- The provider layer already caches, so calling this per scanned item is cheap.
local function LookupItemValue(itemLink)
    if not (activeMode and activeMode.usesItemProtection) then
        return nil, nil
    end
    if not (db and db.priceWarnEnabled and tonumber(db.priceThresholdGold)) then
        return nil, nil
    end
    if not (ns.Prices and ns.Prices.GetValue) then
        return nil, nil
    end
    local copper, _, sourceLabel = ns.Prices.GetValue(itemLink)
    return copper, sourceLabel
end

local function ScanBags()
    wipe(items)
    local validKeys = {}

    for _, bag in ipairs(BAGS_TO_SCAN) do
        local numSlots = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or 0
        for slot = 1, numSlots do
            local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and info.isLocked then
                -- Locked = mid-cast (the disenchant target) or on the cursor.
                -- Keep it OUT of the list/queue, but keep its selection key
                -- VALID: if the cast fails (movement, interrupt), the item
                -- returns on the next scan and must still be checked - before
                -- this, a failed cast silently wiped the user's checkmark.
                validKeys[ComputeItemKey(bag, slot, info.hyperlink)] = true
            elseif info and info.hyperlink then
                local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture, _, _, _, bindType, _, setID = GetItemInfoSafe(info.hyperlink)
                local retryKey = bag .. ":" .. slot
                if itemQuality ~= nil then
                    itemLoadRetries[retryKey] = nil
                end
                if itemQuality == nil then
                    -- Item not in the client cache yet: request it and refresh
                    -- once loaded - but capped, see itemLoadRetries above.
                    local tries = (itemLoadRetries[retryKey] or 0) + 1
                    itemLoadRetries[retryKey] = tries
                    if tries <= MAX_ITEM_LOAD_RETRIES then
                        QueueRefreshWhenItemLoaded(bag, slot)
                    end
                elseif (info.stackCount or 1) >= activeMode.minStack
                    and activeMode.scanEligible(info.hyperlink, itemQuality, info)
                    and not IsBlacklistedItem(info.hyperlink) then
                    local itemLevel = 0
                    if C_Item and C_Item.GetDetailedItemLevelInfo then
                        itemLevel = C_Item.GetDetailedItemLevelInfo(info.hyperlink) or 0
                    elseif GetDetailedItemLevelInfo then
                        itemLevel = GetDetailedItemLevelInfo(info.hyperlink) or 0
                    end

                    local entry = {
                        bag = bag,
                        slot = slot,
                        key = ComputeItemKey(bag, slot, info.hyperlink),
                        link = info.hyperlink,
                        texture = info.iconFileID or itemTexture or 134400,
                        quality = itemQuality,
                        count = info.stackCount or 1,
                        name = GetDisplayName(itemName, info.hyperlink),
                        itemLevel = itemLevel,
                        isSet = (setID ~= nil and setID ~= 0) or nil,
                        -- These materials may be needed for quests; require explicit selection.
                        manualOnly = activeMode.key == "disenchant" and IsForeverDisenchantMaterial(info.hyperlink),
                    }

                    -- Value data for the surface (nil when the guard is off /
                    -- no price known). isValuable is derived once here so the
                    -- surface can read a plain bool; the auto-queue guard uses
                    -- the same IsValuableItem, so they never disagree.
                    entry.priceCopper, entry.priceSource = LookupItemValue(info.hyperlink)
                    entry.isValuable = IsValuableItem(entry)

                    local tagText = GetBindTagText(bindType, info.isBound)
                    if entry.isSet then
                        tagText = (tagText and (tagText .. " ") or "") .. "|cffff7f00SET|r"
                    end
                    entry.bindTag = tagText

                    items[#items + 1] = entry
                    validKeys[entry.key] = true
                end
            end
        end
    end

    for key in pairs(selected) do
        if not validKeys[key] then
            selected[key] = nil
        end
    end

    SortItems()
    BuildQueue()
end

local function UpdateStatusText()
    if not statusText then
        return
    end

    if not activeMode.isKnown() then
        statusText:SetText(L[activeMode.notLearnedTextKey or "STATUS_NOT_LEARNED"] or L["STATUS_NOT_LEARNED"])
        return
    end

    if InCombatLockdown() then
        statusText:SetText(L["STATUS_IN_COMBAT"])
        return
    end

    statusText:SetText(string.format(L["FOUND_COUNT"], #items))
end

local function PreviewForItem(item)
    if not item or not ns.Prediction or not db or db.showExpected == false
        or not activeMode or activeMode.key ~= "disenchant" then return "" end
    local ok, text = pcall(function()
        return ns.Prediction.BuildPreview(ns.Prediction.Estimate(item))
    end)
    return ok and text or ""
end

local function ClearListRow(row)
    row.item = nil
    row.icon:SetTexture(nil)
    row.icon:SetDesaturated(false)
    row.icon:SetVertexColor(1, 1, 1, 1)
    row.checkbox:SetChecked(false)
    row.label:SetText("")
    if row.preview then row.preview:SetText("") end
    if row.bindText then
        row.bindText:SetText("")
    end
    if row.valueText then
        row.valueText:SetText("")
    end
    row:Hide()
end

local function SetListRowItem(row, item)
    row.item = item
    if row.preview then row.preview:SetText(PreviewForItem(item)) end
    local isSelected = selected[item.key] and true or false

    row.icon:SetTexture(item.texture or 134400)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetDesaturated(not isSelected)
    if isSelected then
        row.icon:SetVertexColor(1, 1, 1, 1)
    else
        row.icon:SetVertexColor(0.45, 0.45, 0.45, 1)
    end

    local countText = item.count and item.count > 1 and (" x" .. item.count) or ""
    if (item.itemLevel or 0) > 0 then
        row.label:SetText(string.format("%s (ilvl %d)%s", item.name or L["UNKNOWN"], item.itemLevel or 0, countText))
    else
        row.label:SetText(string.format("%s%s", item.name or L["UNKNOWN"], countText))
    end

    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
    if color then
        row.label:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
    else
        row.label:SetTextColor(1, 1, 1)
    end

    if row.bindText then
        row.bindText:SetText(activeMode.usesItemProtection and (item.bindTag or "") or "")
    end
    if row.valueText then
        if item.isValuable and item.priceCopper and ns.Prices and ns.Prices.FormatGoldIcon then
            -- Coin icon + amount (no "VALUE/WERT" label) - Oliver's design call.
            row.valueText:SetText(ns.Prices.FormatGoldIcon(item.priceCopper))
        else
            row.valueText:SetText("")
        end
    end

    row.checkbox:SetChecked(isSelected)
    row:Show()
end

-- Shared by the row body and its checkbox (the logic was duplicated before and
-- would silently diverge). Blocked in combat: toggling changes the queue, which
-- would need protected operations (secure button attributes, panel layout).
local function ToggleRowSelection(item)
    if not item then
        return
    end
    if InCombatLockdown() then
        Print(L["NOT_IN_COMBAT"])
        return
    end
    local key = item.key
    selected[key] = not selected[key] or nil
    BuildQueue()
    if mainFrame and mainFrame:IsShown() then
        UpdateStatusText()
    end
    if mainFrame then
        mainFrame:RefreshUI()
    end
end

local function CreateListRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.14)
    row.bg = bg

    local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    checkbox:SetSize(22, 22)
    checkbox:SetPoint("LEFT", 0, 0)
    row.checkbox = checkbox

    local iconBorder = CreateIconBorder(row, 24)
    iconBorder:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    iconBorder:SetFrameLevel(row:GetFrameLevel() + 1)
    row.iconBorder = iconBorder

    local icon = iconBorder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    row.icon = icon

    local bindText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bindText:SetPoint("RIGHT", row, "RIGHT", -8, 8)
    bindText:SetWidth(56)
    bindText:SetJustifyH("RIGHT")
    row.bindText = bindText

    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueText:SetPoint("RIGHT", bindText, "LEFT", -6, 0)
    valueText:SetWidth(112)
    valueText:SetJustifyH("RIGHT")
    valueText:SetTextColor(1, 0.82, 0)
    row.valueText = valueText

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", iconBorder, "RIGHT", 8, 8)
    label:SetPoint("RIGHT", valueText, "LEFT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label

    local preview = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    preview:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    preview:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    preview:SetJustifyH("LEFT")
    preview:SetWordWrap(false)
    preview:SetTextColor(0.75, 0.8, 0.9)
    row.preview = preview

    checkbox:SetScript("OnClick", function(self)
        local parentRow = self:GetParent()
        ToggleRowSelection(parentRow and parentRow.item)
        -- Undo the checkbox's own visual toggle if the selection was refused
        -- (in combat) - the refresh below re-syncs it either way.
        if parentRow and parentRow.item then
            self:SetChecked(selected[parentRow.item.key] == true)
        end
    end)

    row:SetScript("OnClick", function(self)
        ToggleRowSelection(self.item)
    end)

    row:SetScript("OnEnter", function(self)
        if not self.item then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(self.item.bag, self.item.slot)
        if self.item.isValuable and self.item.priceCopper and self.item.priceSource
            and ns.Prices and ns.Prices.FormatGold then
            GameTooltip:AddLine(string.format(L["VALUE_TOOLTIP"],
                ns.Prices.FormatGold(self.item.priceCopper), self.item.priceSource), 1, 0.82, 0)
        end
        if ns.Prediction and activeMode and activeMode.key == "disenchant" and db and db.showExpected ~= false then
            ns.Prediction.AppendToTooltip(GameTooltip, self.item)
        end
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row:Hide()
    return row
end

local function CreateQueueRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(24)

    local iconBorder = CreateIconBorder(row, 20)
    iconBorder:SetPoint("LEFT", 0, 0)
    row.iconBorder = iconBorder

    local icon = iconBorder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    row.icon = icon

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", iconBorder, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label

    row:Hide()
    return row
end

local function UpdateListRows()
    if not listScrollFrame or not listScrollChild then
        return
    end

    local width = math.max(100, (listScrollFrame:GetWidth() or 0) - 24)
    local y = 0

    for index, item in ipairs(items) do
        local row = listRows[index]
        if not row then
            row = CreateListRow(listScrollChild)
            listRows[index] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", listScrollChild, "TOPLEFT", 0, -y)
        row:SetWidth(width)
        SetListRowItem(row, item)
        local height = activeMode.key == "disenchant" and db.showExpected ~= false and 54 or ROW_HEIGHT
        row:SetHeight(height)
        y = y + height + ROW_SPACING
    end

    for index = #items + 1, #listRows do
        -- Full clear, not just Hide: a hidden row otherwise keeps its stale
        -- item reference (and checkbox state) until it is reused.
        ClearListRow(listRows[index])
    end

    local totalHeight = math.max(listScrollFrame:GetHeight() or 1, y)
    listScrollChild:SetSize(width, totalHeight)
end

local function UpdateQueueRows()
    if not queueScrollFrame or not queueScrollChild then
        return
    end

    local width = math.max(100, (queueScrollFrame:GetWidth() or 0) - 24)
    local y = 0

    for index, item in ipairs(queue) do
        local row = queueRows[index]
        if not row then
            row = CreateQueueRow(queueScrollChild)
            queueRows[index] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", queueScrollChild, "TOPLEFT", 0, -y)
        row:SetWidth(width)
        row.icon:SetTexture(item.texture or 134400)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local labelText = item.name or L["UNKNOWN"]
        if index == 1 then
            row.label:SetText("1. " .. labelText)
            row.label:SetTextColor(1, 0.82, 0)
        else
            row.label:SetText(index .. ". " .. labelText)
            row.label:SetTextColor(0.9, 0.9, 0.9)
        end

        row:Show()
        y = y + 26
    end

    for index = #queue + 1, #queueRows do
        queueRows[index]:Hide()
    end

    local totalHeight = math.max(queueScrollFrame:GetHeight() or 1, y)
    queueScrollChild:SetSize(width, totalHeight)
end

local function IsSecretValue(value)
    -- Older Classic clients do not expose the secret-value API.
    return issecretvalue and issecretvalue(value) or false
end

local function ClassifyDisenchantFailure(message)
    if IsSecretValue(message) or type(message) ~= "string" or message == "" then
        return nil
    end

    local cleaned = string.lower(StripColorCodes(message))
    local cantBeDisenchanted = type(ERR_CANT_BE_DISENCHANTED) == "string" and string.lower(ERR_CANT_BE_DISENCHANTED) or nil
    local invalidItemTarget = type(ERR_INVALID_ITEM_TARGET) == "string" and string.lower(ERR_INVALID_ITEM_TARGET) or nil

    if cantBeDisenchanted and cleaned == cantBeDisenchanted then
        return "hard"
    end

    if invalidItemTarget and cleaned == invalidItemTarget then
        return "generic"
    end

    if cleaned:find("cannot be disenchanted", 1, true) or cleaned:find("can not be disenchanted", 1, true) then
        return "hard"
    end

    if cleaned:find("not a valid target", 1, true) or cleaned:find("invalid target", 1, true) then
        return "generic"
    end

    if cleaned:find("kein gültiges ziel", 1, true) or cleaned:find("ungueltiges ziel", 1, true) or cleaned:find("ungültiges ziel", 1, true) then
        return "generic"
    end

    if cleaned:find("disenchant", 1, true) and (
        cleaned:find("cannot", 1, true) or
        cleaned:find("can't", 1, true) or
        cleaned:find("cant", 1, true) or
        cleaned:find("not", 1, true)
    ) then
        return "hard"
    end

    if cleaned:find("entzauber", 1, true) and (
        cleaned:find("nicht", 1, true) or
        cleaned:find("kein", 1, true) or
        cleaned:find("kann", 1, true)
    ) then
        return "hard"
    end

    return nil
end

-- ===================================================================
-- Processing modes (1.6.0)
-- ===================================================================
-- Disenchanting, milling and prospecting are all "bag-target" casts that share
-- this engine: a secure cast on a bag slot, driven by the same scan -> queue ->
-- arm -> BAG_UPDATE -> rescan loop. A mode descriptor captures the only things
-- that differ per mode, so the engine stays a single code path while each client
-- exposes only the profession abilities it actually supports.
--
-- Descriptor fields:
--   key                stable id (DB and per-mode blacklist namespace)
--   spellID            the bag-target spell to cast
--   minStack           units one cast needs in a single slot (DE 1, mill/prosp 5)
--   usesItemProtection value/set/ilvl/binding protection applies? (DE only)
--   buttonTextKey/countTextKey  locale keys for the cast button
--   spellName()/icon() live lookups for the secure "spell" attribute and the icon
--   isAvailable()      spell exists on THIS client (hides unsupported modes)
--   isKnown()          the character currently knows the ability
--   scanEligible(link, quality, info)  mode-intrinsic eligibility for one slot
--   classifyFailure(msg)  map an error line to hard/generic/nil for the blacklist
local DISENCHANT_MODE = {
    key                = "disenchant",
    spellID            = SPELL_ID_DISENCHANT,
    minStack           = 1,
    usesItemProtection = true,
    buttonTextKey      = "DISENCHANT",
    countTextKey       = "DISENCHANT_COUNT",
    modeNameKey        = "MODE_DISENCHANT",
    subtitleTextKey    = "SUBTITLE",
    emptyTextKey       = "COMPACT_EMPTY",
    notLearnedTextKey  = "STATUS_NOT_LEARNED",
    queueNotLearnedKey = "QUEUE_NOT_LEARNED",
    blacklistHintKey   = "COMPACT_BLACKLIST_HINT",
    -- Compact-bar queue line (Sol's request: the surface reads this instead of
    -- branching on mode.key). Disenchant keeps the existing COMPACT_QUEUE string.
    queueTextKey       = "COMPACT_QUEUE",
    spellName          = function() return GetSpellNameSafe(SPELL_ID_DISENCHANT) end,
    icon               = function() return GetSpellTextureSafe(SPELL_ID_DISENCHANT) end,
    isAvailable        = function() return GetSpellNameSafe(SPELL_ID_DISENCHANT) ~= nil end,
    isKnown            = PlayerKnowsDisenchant,
    scanEligible       = function(itemLink, itemQuality)
        -- Keep the quality filter for equipment and explicit Forever exceptions.
        return IsReasonablyDisenchantable(itemLink, itemQuality) and IsQualityEnabled(itemQuality)
    end,
    classifyFailure    = ClassifyDisenchantFailure,
}

-- Milling and prospecting share the disenchant engine (bag-target cast, 5 units
-- per cast). usesItemProtection = false keeps value/set/ilvl protection out.
-- Every visible surface string is selected by the descriptor, so the shared UI
-- never needs to branch on mode.key.
local MILLING_MODE = {
    key                = "milling",
    spellID            = SPELL_ID_MILLING,
    minStack           = 5,
    usesItemProtection = false,
    buttonTextKey      = "MILL",
    countTextKey       = "MILL_COUNT",
    modeNameKey        = "MODE_MILLING",
    subtitleTextKey    = "SUBTITLE_MILLING",
    emptyTextKey       = "COMPACT_EMPTY_MILLING",
    notLearnedTextKey  = "MODE_NOT_LEARNED_HINT",
    queueNotLearnedKey = "MODE_NOT_LEARNED_HINT",
    blacklistHintKey   = "COMPACT_BLACKLIST_HINT_MILLING",
    queueTextKey       = "COMPACT_QUEUE_MILLING",
    spellName          = function() return GetSpellNameSafe(SPELL_ID_MILLING) end,
    icon               = function() return GetSpellTextureSafe(SPELL_ID_MILLING) end,
    isAvailable        = function() return IS_NON_RETAIL_CLIENT and GetSpellNameSafe(SPELL_ID_MILLING) ~= nil end,
    isKnown            = function() return PlayerKnowsSpellID(SPELL_ID_MILLING) end,
    scanEligible       = function(itemLink) return IsMillableHerb(itemLink) end,
    classifyFailure    = function() return nil end,  -- FIRST CUT: never auto-blacklist materials
}

local PROSPECTING_MODE = {
    key                = "prospecting",
    spellID            = SPELL_ID_PROSPECTING,
    minStack           = 5,
    usesItemProtection = false,
    buttonTextKey      = "PROSPECT",
    countTextKey       = "PROSPECT_COUNT",
    modeNameKey        = "MODE_PROSPECTING",
    subtitleTextKey    = "SUBTITLE_PROSPECTING",
    emptyTextKey       = "COMPACT_EMPTY_PROSPECTING",
    notLearnedTextKey  = "MODE_NOT_LEARNED_HINT",
    queueNotLearnedKey = "MODE_NOT_LEARNED_HINT",
    blacklistHintKey   = "COMPACT_BLACKLIST_HINT_PROSPECTING",
    queueTextKey       = "COMPACT_QUEUE_PROSPECTING",
    spellName          = function() return GetSpellNameSafe(SPELL_ID_PROSPECTING) end,
    icon               = function() return GetSpellTextureSafe(SPELL_ID_PROSPECTING) end,
    isAvailable        = function() return IS_NON_RETAIL_CLIENT and GetSpellNameSafe(SPELL_ID_PROSPECTING) ~= nil end,
    isKnown            = function() return PlayerKnowsSpellID(SPELL_ID_PROSPECTING) end,
    scanEligible       = function(itemLink) return IsProspectableOre(itemLink) end,
    classifyFailure    = function() return nil end,  -- FIRST CUT: never auto-blacklist materials
}

ns.Modes = {
    list    = { DISENCHANT_MODE, MILLING_MODE, PROSPECTING_MODE },
    byKey   = { disenchant = DISENCHANT_MODE, milling = MILLING_MODE, prospecting = PROSPECTING_MODE },
    default = DISENCHANT_MODE,
}

local function IsModeAvailable(mode)
    return mode and (not mode.isAvailable or mode.isAvailable())
end

local function GetAvailableModes()
    local available = {}
    for _, mode in ipairs(ns.Modes.list) do
        if IsModeAvailable(mode) then
            available[#available + 1] = mode
        end
    end
    return available
end

local function ResolveMode(modeKey)
    local mode = modeKey and ns.Modes.byKey[modeKey]
    -- Stored keys can outlive a client or profession. Prefer the configured
    -- default when available, then fall back to the first client-valid mode.
    if not IsModeAvailable(mode) then
        mode = IsModeAvailable(ns.Modes.default) and ns.Modes.default or GetAvailableModes()[1]
    end
    return mode or ns.Modes.default
end

-- Pure setter: select the mode and remember it. No combat guard and no refresh -
-- used at load (ADDON_LOADED), before the frames and queue exist.
local function ApplyMode(modeKey)
    activeMode = ResolveMode(modeKey)
    if db then
        db.activeMode = activeMode.key
    end
    UpdateBindingName(activeMode.buttonTextKey)
    return activeMode
end

-- User-facing switch (the surface calls ns.Modes.SetActive). Changing the mode
-- rebuilds the secure cast button for a different spell, which is protected in
-- combat - so it politely refuses during lockdown (the single combat guard for
-- switching). Out of combat it applies the mode, drops the manual selection and
-- rescans, so the queue and armed target belong to the new mode.
local function SetActiveMode(modeKey)
    if InCombatLockdown() then
        Print(L["MODE_CHANGE_IN_COMBAT"] or L["NOT_IN_COMBAT"])
        return activeMode, false
    end
    local requestedMode = ns.Modes.byKey[modeKey]
    if not IsModeAvailable(requestedMode) then
        return activeMode, false
    end
    if requestedMode == activeMode then
        return activeMode, true
    end
    -- A delayed failure from the previous spell must never be classified or
    -- blacklisted under the newly selected mode.
    ClearPendingDisenchant()
    pendingLootUntil = 0
    nextAllowedQueueClickAt = 0
    ApplyMode(modeKey)
    wipe(selected)
    if RefreshList then
        RefreshList()
    end
    -- The blacklist window is per-mode now; if it is open, show the new mode's list.
    if blacklistFrame and blacklistFrame:IsShown() and RefreshBlacklistUI then
        RefreshBlacklistUI()
    end
    return activeMode, true
end

-- Safe default until EnsureDB + ApplyMode run in ADDON_LOADED.
activeMode = ns.Modes.default
ns.Modes.GetActive = function() return activeMode end
ns.Modes.GetAvailable = GetAvailableModes
ns.Modes.SetActive = SetActiveMode


local function ExtractMessageFromEventArgs(...)
    local numArgs = select("#", ...)
    for i = numArgs, 1, -1 do
        local value = select(i, ...)
        if not IsSecretValue(value) and type(value) == "string" and value ~= "" then
            return value
        end
    end
    return nil
end

ValidatePendingItemForBlacklist = function(delaySeconds)
    if not pendingDisenchantItem then
        return
    end

    pendingValidationToken = pendingValidationToken + 1
    local token = pendingValidationToken
    local delay = tonumber(delaySeconds) or 0.2

    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            if token ~= pendingValidationToken then
                return
            end

            local item = pendingDisenchantItem
            if not item then
                return
            end

            if not DoesPendingItemStillExist(item) then
                ClearPendingDisenchant()
                if mainFrame and mainFrame:IsShown() then
                    RefreshList()
                end
                return
            end

            local validationItem = {
                bag = item.bag,
                slot = item.slot,
                link = GetBagItemLinkSafe(item.bag, item.slot) or item.link,
            }

            if TooltipSaysCantDisenchant(validationItem) then
                AddPendingItemToBlacklist()
            else
                ClearPendingDisenchant()
                if mainFrame and mainFrame:IsShown() then
                    RefreshList()
                end
            end
        end)
    end
end

local function AddItemToBlacklist(item, messagePrefix)
    if not item or not db or not db.blacklist then
        return
    end

    local blacklistKey = GetBlacklistKeyFromLink(item.link)
    if blacklistKey then
        GetModeBlacklist()[blacklistKey] = true
    end

    if item.key then
        selected[item.key] = nil
    end

    BuildQueue()
    if messagePrefix ~= false then
        Print(string.format("%s: %s", messagePrefix or L["ADDED_AUTO"], item.name or L["UNKNOWN"]))
    end

    ScanBags()
    if blacklistFrame and blacklistFrame:IsShown() and RefreshBlacklistUI then
        RefreshBlacklistUI()
    end
    RefreshUI()
end

AddPendingItemToBlacklist = function()
    local item = pendingDisenchantItem
    if not item then
        ClearPendingDisenchant()
        return
    end

    pendingValidationToken = pendingValidationToken + 1
    AddItemToBlacklist(item, L["ADDED_AUTO"])
    ClearPendingDisenchant()
end


local function TryBlacklistQueuedItemBeforeCast()
    local item = queue and queue[1]
    if not item then
        return false
    end

    if TooltipSaysCantDisenchant(item) then
        SetPendingDisenchant(item)
        AddPendingItemToBlacklist()
        return true
    end

    return false
end

local function UpdateQueueButtonVisual(enabled, label)
    if not queueButton then
        return
    end

    if queueButtonText then
        queueButtonText:SetText(label or L["DISENCHANT"])
    end

    if enabled then
        if queueButton.Left and queueButton.Middle and queueButton.Right then
            queueButton.Left:SetAlpha(1)
            queueButton.Middle:SetAlpha(1)
            queueButton.Right:SetAlpha(1)
        end
        if queueButtonText then
            queueButtonText:SetTextColor(1, 0.82, 0)
        end
    else
        if queueButton.Left and queueButton.Middle and queueButton.Right then
            queueButton.Left:SetAlpha(0.55)
            queueButton.Middle:SetAlpha(0.55)
            queueButton.Right:SetAlpha(0.55)
        end
        if queueButtonText then
            queueButtonText:SetTextColor(0.7, 0.7, 0.7)
        end
    end
end

local function ClearQueueButtonAttributes()
    if not queueButton then
        return
    end
    -- SetAttribute on a secure frame is a PROTECTED operation in combat -
    -- attempting it raises "Interface action failed". The guard lives HERE so
    -- every caller is covered at once. During combat the already armed compact
    -- action deliberately remains available; any rebuild waits for combat end.
    if InCombatLockdown() then
        return
    end

    queueButton:SetAttribute("type", nil)
    queueButton:SetAttribute("spell", nil)
    queueButton:SetAttribute("target-item", nil)
    queueButton:SetAttribute("target-bag", nil)
    queueButton:SetAttribute("target-slot", nil)
end

-- Fire the secure action exactly ONCE per click: register only the click edge
-- the client actually acts on (the "cast on key down" CVar). This replaces the
-- old timer workaround - with both edges registered plus a plain "type"
-- attribute, the cast used to fire twice per click.
local function UpdateQueueButtonClickRegistration()
    if not queueButton or InCombatLockdown() then
        return
    end
    -- Remember which edge we registered: WoW has no "GetRegisteredClicks",
    -- so the self-check needs this note to compare against the live CVar.
    if GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") then
        queueButton:RegisterForClicks("AnyDown")
        queueButton.dehClickEdge = "AnyDown"
    else
        queueButton:RegisterForClicks("AnyUp")
        queueButton.dehClickEdge = "AnyUp"
    end
end

local function UpdateQueueButton()
    if not queueButton then
        return
    end

    local label = #queue > 1 and string.format(L[activeMode.countTextKey], #queue) or L[activeMode.buttonTextKey]

    -- One disarm path for all three "cannot cast right now" cases below -
    -- the sequence was copy-pasted three times before and only differed in
    -- the label and the explanatory info text.
    local function Disarm(buttonLabel, infoText)
        queueButton:Disable()
        if manualBlacklistButton then
            manualBlacklistButton:Disable()
        end
        ClearQueueButtonAttributes()
        UpdateQueueButtonVisual(false, buttonLabel)
        if queueInfoText then
            queueInfoText:SetText(infoText)
        end
    end

    if InCombatLockdown() then
        -- Secure attributes cannot be rebuilt during lockdown. Keep the
        -- already armed compact button untouched: disenchanting in combat is
        -- allowed when the player deliberately chooses to do it.
        return
    end

    if not activeMode.isKnown() then
        Disarm(label, L[activeMode.queueNotLearnedKey or "QUEUE_NOT_LEARNED"] or L["QUEUE_NOT_LEARNED"])
        return
    end

    local item = queue[1]
    if not item then
        Disarm(L[activeMode.buttonTextKey], L["QUEUE_EMPTY"])
        return
    end

    local spellCastName = activeMode.spellName() or L[activeMode.buttonTextKey]
    local targetItem = string.format("%d %d", item.bag, item.slot)

    ClearQueueButtonAttributes()
    UpdateQueueButtonClickRegistration()
    -- Plain "type" - the mechanism the 1.3 line has proven in the field.
    -- Single-fire is guaranteed by the click registration above, not by a
    -- release-only attribute (typerelease silently did nothing on some clients).
    queueButton:SetAttribute("type", "spell")
    queueButton:SetAttribute("spell", spellCastName)
    queueButton:SetAttribute("target-item", targetItem)
    queueButton:SetAttribute("target-bag", item.bag)
    queueButton:SetAttribute("target-slot", item.slot)
    queueButton:Enable()
    if manualBlacklistButton then
        manualBlacklistButton:Enable()
    end
    UpdateQueueButtonVisual(true, label)

    if queueInfoText then
        queueInfoText:SetText(string.format(L["QUEUE_NEXT"], item.name or L["UNKNOWN"]))
    end
end

local function UpdateLayout()
    if not mainFrame or not listPanel or not queuePanel then
        return
    end

    local topOffset = modeTabFrame and modeTabFrame:IsShown() and -82 or -56

    queuePanel:ClearAllPoints()
    queuePanel:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -16, topOffset)
    queuePanel:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -16, 56)
    queuePanel:SetWidth(QUEUE_PANEL_WIDTH)

    listPanel:ClearAllPoints()
    listPanel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 16, topOffset)
    listPanel:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 16, 56)

    if #queue > 0 then
        queuePanel:Show()
        listPanel:SetPoint("RIGHT", queuePanel, "LEFT", -12, 0)
    else
        queuePanel:Hide()
        -- y is 0, not 56: RIGHT only controls the horizontal edge here (the
        -- vertical extent is pinned by TOPLEFT/BOTTOMLEFT); the old copy-pasted
        -- 56 was ignored by the layout engine and only confused readers.
        listPanel:SetPoint("RIGHT", mainFrame, "RIGHT", -16, 0)
    end
end

RefreshUI = function()
    if not mainFrame then
        return
    end

    if UpdateModeSurface then
        UpdateModeSurface()
    end

    -- queuePanel is an ancestor of the secure button, so Show/Hide/SetPoint on
    -- it are protected in combat (protection propagates to parents). Rows and
    -- texts are fine to update; the layout catches up after combat.
    if not InCombatLockdown() then
        UpdateLayout()
    end
    UpdateListRows()
    UpdateQueueRows()
    UpdateStatusText()
    UpdateQueueButton()
    UpdateCompactFrame()
end

RefreshList = function()
    if InCombatLockdown() then
        needsRefreshAfterCombat = true
        UpdateStatusText()
        UpdateQueueButton()
        return
    end

    ScanBags()
    RefreshUI()
end

local function DockQueueButtonToCompact()
    if not queueButton or not compactFrame or not compactFullButton then
        return
    end
    if InCombatLockdown() then
        return
    end
    queueButton:SetParent(compactFrame)
    queueButton:ClearAllPoints()
    queueButton:SetPoint("RIGHT", compactFullButton, "LEFT", -6, 0)
    queueButton:SetSize(130, 24)
end

local function DockQueueButtonToPanel()
    if not queueButton or not queuePanel then
        return
    end
    if InCombatLockdown() then
        return
    end
    queueButton:SetParent(queuePanel)
    queueButton:ClearAllPoints()
    queueButton:SetPoint("BOTTOMLEFT", queuePanel, "BOTTOMLEFT", 16, 12)
    queueButton:SetSize(138, 24)
end

local function GetCompactSkippedText()
    local skipped = ns.GetValuableSkippedCount and ns.GetValuableSkippedCount() or 0
    if skipped == 1 then
        return L["COMPACT_SKIPPED_ONE"]
    elseif skipped > 1 then
        return string.format(L["COMPACT_SKIPPED_MANY"], skipped)
    end
    return nil
end

UpdateCompactFrame = function()
    if not compactFrame or not compactFrame:IsShown() then
        return
    end

    local item = queue[1]
    local skippedText = GetCompactSkippedText()
    compactFrame.currentItem = item
    local preview = PreviewForItem(item)
    if compactPreviewText then compactPreviewText:SetText(preview) end
    if item then
        compactIcon:SetTexture(item.texture or 134400)
        compactIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local compactLabel = item.name or L["UNKNOWN"]
        if activeMode.usesItemProtection and item.bindTag then
            compactLabel = compactLabel .. "  " .. item.bindTag
        end
        compactNameText:SetText(compactLabel)

        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
        if color then
            compactNameText:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
        else
            compactNameText:SetTextColor(1, 1, 1)
        end

        local queueLabel = string.format(L[activeMode.queueTextKey], #queue)
        if skippedText then
            queueLabel = queueLabel .. "  |  " .. skippedText
        end
        compactQueueText:SetText(queueLabel)
    else
        compactIcon:SetTexture((activeMode.icon and activeMode.icon()) or 134400)
        compactIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        compactNameText:SetText(L[activeMode.emptyTextKey or "COMPACT_EMPTY"] or L["COMPACT_EMPTY"])
        compactNameText:SetTextColor(0.7, 0.7, 0.7)
        compactQueueText:SetText(skippedText or "")
    end

    -- Fit the bar to whichever line is wider. The skipped-value message is
    -- often longer than the item name and must not run under the cast button.
    local nameWidth = compactNameText:GetStringWidth() or 0
    local queueWidth = compactQueueText:GetStringWidth() or 0
    local contentWidth = math.max(nameWidth, queueWidth)
    local modeWidth = compactModeSelector and compactModeSelector:IsShown() and 98 or 0
    -- Compact owns a secure button: dimensions may only change out of combat.
    if not InCombatLockdown() then
        compactFrame:SetHeight(preview ~= "" and 84 or 58)
        local previewWidth = compactPreviewText and compactPreviewText:GetStringWidth() or 0
        compactFrame:SetWidth(math.max(400 + modeWidth, math.min(620 + modeWidth,
            math.max(math.floor(contentWidth + 0.5) + 278 + modeWidth, previewWidth + 28))))
    end
end

SetCompactMode = function(enabled)
    if not compactFrame or not queueButton or not queuePanel then
        return
    end

    if InCombatLockdown() then
        Print(L["NOT_IN_COMBAT"])
        return
    end

    db.compactMode = enabled and true or false

    if enabled then
        if mainFrame then
            mainFrame:Hide()
        end
        DockQueueButtonToCompact()
        compactFrame:Show()
        RefreshList()
    else
        compactFrame:Hide()
        DockQueueButtonToPanel()
        if mainFrame then
            mainFrame:Show()
            RefreshList()
        end
    end
end

local function GetBlacklistEntries()
    local result = {}
    if not db or type(db.blacklist) ~= "table" then
        return result
    end

    for blacklistKey, isBlacklisted in pairs(GetModeBlacklist()) do
        if isBlacklisted then
            local itemRef
            if tostring(blacklistKey):match("^%d+$") then
                itemRef = "item:" .. tostring(blacklistKey)
            else
                itemRef = tostring(blacklistKey)
            end

            local itemName, itemLink, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfoSafe(itemRef)
            local displayName = GetDisplayName(itemName, itemLink or itemRef)
            if not displayName or displayName == "" or displayName == L["UNKNOWN_ITEM"] then
                displayName = tostring(blacklistKey)
            end

            result[#result + 1] = {
                key = blacklistKey,
                link = itemLink or itemRef,
                name = displayName,
                quality = itemQuality,
                texture = itemTexture or 134400,
            }
        end
    end

    table.sort(result, function(a, b)
        return tostring(a.name or "") < tostring(b.name or "")
    end)

    return result
end

local function CreateBlacklistRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(26)

    local iconBorder = CreateIconBorder(row, 20)
    iconBorder:SetPoint("LEFT", 0, 0)
    row.iconBorder = iconBorder

    local icon = iconBorder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    row.icon = icon

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", iconBorder, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -70, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label

    local removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    removeButton:SetSize(56, 20)
    removeButton:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    removeButton:SetText(L["DELETE"])
    row.removeButton = removeButton

    removeButton:SetScript("OnClick", function(self)
        local entry = self:GetParent().entry
        if not entry or not db or not db.blacklist then
            return
        end
        GetModeBlacklist()[entry.key] = nil
        Print(string.format(L["REMOVED_FROM_BLACKLIST"], entry.name or L["UNKNOWN"]))
        if RefreshBlacklistUI then
            RefreshBlacklistUI()
        end
        RefreshList()
    end)

    row:SetScript("OnEnter", function(self)
        if not self.entry or not self.entry.link then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.entry.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row:Hide()
    return row
end

RefreshBlacklistUI = function()
    if not blacklistFrame or not blacklistScrollFrame or not blacklistScrollChild then
        return
    end

    local entries = GetBlacklistEntries()
    local width = math.max(100, (blacklistScrollFrame:GetWidth() or 0) - 24)
    local y = 0

    for index, entry in ipairs(entries) do
        local row = blacklistRows[index]
        if not row then
            row = CreateBlacklistRow(blacklistScrollChild)
            blacklistRows[index] = row
        end

        row.entry = entry
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", blacklistScrollChild, "TOPLEFT", 0, -y)
        row:SetWidth(width)
        row.icon:SetTexture(entry.texture or 134400)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.label:SetText(entry.name or L["UNKNOWN"])

        local color = entry.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.quality]
        if color then
            row.label:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
            row.iconBorder:SetBackdropBorderColor(color.r or 1, color.g or 1, color.b or 1, 1)
        else
            row.label:SetTextColor(1, 1, 1)
            row.iconBorder:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end

        row:Show()
        y = y + 28
    end

    for index = #entries + 1, #blacklistRows do
        blacklistRows[index]:Hide()
    end

    if blacklistEmptyText then
        if #entries == 0 then
            blacklistEmptyText:Show()
        else
            blacklistEmptyText:Hide()
        end
    end

    blacklistScrollChild:SetSize(width, math.max(blacklistScrollFrame:GetHeight() or 1, y))
end

ToggleBlacklistFrame = function()
    if not blacklistFrame then
        return
    end

    if blacklistFrame:IsShown() then
        blacklistFrame:Hide()
    else
        blacklistFrame:ClearAllPoints()
        if mainFrame and mainFrame:IsShown() then
            blacklistFrame:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 20, -12)
        else
            blacklistFrame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
        end
        blacklistFrame:Show()
        blacklistFrame:Raise()
        RefreshBlacklistUI()
    end
end

local function ToggleMainFrame()
    -- Both windows can host the secure button, which makes Show/Hide on them
    -- protected while in combat - opening/closing must wait for combat to end.
    if InCombatLockdown() then
        Print(L["NOT_IN_COMBAT"])
        return
    end

    if db and db.compactMode and compactFrame then
        if compactFrame:IsShown() then
            compactFrame:Hide()
        else
            DockQueueButtonToCompact()
            compactFrame:Show()
            RefreshList()
        end
        return
    end

    if not mainFrame then
        return
    end

    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        RefreshList()
    end
end

local function RaiseAddonWindows(clicked)
    local order = { mainFrame, settingsFrame, blacklistFrame }
    for _, frame in ipairs(order) do
        if frame and frame:IsShown() and frame ~= clicked then
            frame:Raise()
        end
    end
    if clicked and clicked ~= mainFrame and clicked:IsShown() then
        clicked:Raise()
    end
end

-- Builds a window in the slim, semi-transparent look of the compact bar:
-- custom backdrop, custom title bar (doubling as drag handle) and a close
-- button. The returned frame exposes .title (FontString), .TitleBar and
-- .CloseButton so other code can anchor to them.
local function CreateStyledWindow(globalName, width, height, extraTemplate)
    -- extraTemplate lets a caller mix in an additional frame template (e.g. the
    -- main window adds SecureHandlerStateTemplate so a state driver can hide it
    -- in combat). The default look/behaviour is unchanged for every other window.
    local template = "BackdropTemplate"
    if extraTemplate and extraTemplate ~= "" then
        template = template .. "," .. extraTemplate
    end
    local f = CreateFrame("Frame", globalName, UIParent, template)
    f:SetSize(width, height)
    f:SetBackdrop(BACKDROP_WINDOW)
    f:SetBackdropColor(0, 0, 0, 0.82)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    -- All addon windows share the normal strata like Blizzard windows;
    -- SetToplevel: the clicked window rises to the front automatically
    f:SetToplevel(true)
    f:SetScript("OnMouseDown", function(self)
        RaiseAddonWindows(self)
    end)

    -- The title bar doubles as the drag handle
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", -4, -4)
    titleBar:SetHeight(28)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnMouseDown", function()
        RaiseAddonWindows(f)
    end)
    titleBar:SetScript("OnDragStart", function()
        f:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
    end)
    f.TitleBar = titleBar

    local titleHighlight = titleBar:CreateTexture(nil, "ARTWORK")
    titleHighlight:SetAllPoints()
    titleHighlight:SetColorTexture(1, 1, 1, 0.04)

    local titleDivider = f:CreateTexture(nil, "ARTWORK")
    titleDivider:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    titleDivider:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    titleDivider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    titleDivider:SetHeight(1)

    local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", 1, 1)
    -- Raise above the title bar: it is a mouse-enabled drag handle overlapping
    -- this corner, and if it wins the click the X feels shifted (part of the
    -- X's area starts a drag instead of closing).
    closeButton:SetFrameLevel(titleBar:GetFrameLevel() + 5)
    closeButton:SetScript("OnClick", function()
        -- Hiding a window that (currently) hosts the secure button is a
        -- protected operation in combat; explain instead of erroring.
        if InCombatLockdown() and f:IsProtected() then
            Print(L["NOT_IN_COMBAT"])
            return
        end
        f:Hide()
    end)
    f.CloseButton = closeButton

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
    title:SetJustifyH("LEFT")
    title:SetJustifyV("MIDDLE")
    f.title = title

    return f
end

local function GetModeName(mode)
    return (mode and mode.modeNameKey and L[mode.modeNameKey]) or (mode and mode.key) or L["UNKNOWN"]
end

local function SelectModeFromSurface(mode)
    if not mode or not ns.Modes or not ns.Modes.SetActive then
        return
    end
    local _, changed = ns.Modes.SetActive(mode.key)
    if changed and compactModeMenu then
        compactModeMenu:Hide()
    end
end

local function CreateModeTabs()
    modeTabFrame = CreateFrame("Frame", nil, mainFrame)
    modeTabFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 16, -52)
    modeTabFrame:SetHeight(24)

    local previous
    for _, mode in ipairs(GetAvailableModes()) do
        local button = CreateFrame("Button", nil, modeTabFrame, "UIPanelButtonTemplate")
        button:SetSize(118, 22)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            button:SetPoint("LEFT", modeTabFrame, "LEFT", 0, 0)
        end
        button:SetText(GetModeName(mode))
        button.mode = mode
        button:SetScript("OnClick", function(self)
            SelectModeFromSurface(self.mode)
        end)
        button:SetScript("OnEnter", function(self)
            if self.mode and not self.mode.isKnown() then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(GetModeName(self.mode))
                GameTooltip:AddLine(L["MODE_NOT_LEARNED_HINT"], 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        modeTabButtons[#modeTabButtons + 1] = button
        previous = button
    end

    modeTabFrame:SetWidth(math.max(1, #modeTabButtons * 124))
end

local function CreateCompactModeMenu()
    compactModeMenu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    compactModeMenu:SetBackdrop(BACKDROP_PANEL)
    compactModeMenu:SetBackdropColor(0, 0, 0, 0.94)
    compactModeMenu:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    compactModeMenu:SetFrameStrata("DIALOG")
    compactModeMenu:Hide()

    local available = GetAvailableModes()
    compactModeMenu:SetSize(132, math.max(30, #available * 24 + 8))
    for index, mode in ipairs(available) do
        local button = CreateFrame("Button", nil, compactModeMenu, "UIPanelButtonTemplate")
        button:SetPoint("TOPLEFT", 4, -4 - (index - 1) * 24)
        button:SetPoint("TOPRIGHT", -4, -4 - (index - 1) * 24)
        button:SetHeight(22)
        button:SetText(GetModeName(mode))
        button.mode = mode
        button:SetScript("OnClick", function(self)
            SelectModeFromSurface(self.mode)
        end)
        button:SetScript("OnEnter", function(self)
            if self.mode and not self.mode.isKnown() then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText(GetModeName(self.mode))
                GameTooltip:AddLine(L["MODE_NOT_LEARNED_HINT"], 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        compactModeMenuButtons[#compactModeMenuButtons + 1] = button
    end
end

UpdateModeSurface = function()
    local available = GetAvailableModes()
    local multipleModes = #available > 1
    local canChangeProtectedLayout = not InCombatLockdown()

    if mainSubtitle then
        mainSubtitle:SetText(L[activeMode.subtitleTextKey or "SUBTITLE"] or L["SUBTITLE"])
    end

    if modeTabFrame and canChangeProtectedLayout then
        if multipleModes then
            modeTabFrame:Show()
        else
            modeTabFrame:Hide()
        end
        for _, button in ipairs(modeTabButtons) do
            local mode = button.mode
            local isActive = mode == activeMode
            local isKnown = mode and mode.isKnown()
            if not isActive and isKnown then
                button:Enable()
            else
                button:Disable()
            end
            local label = button:GetFontString()
            if label then
                if isActive then
                    label:SetTextColor(1, 0.82, 0)
                elseif isKnown then
                    label:SetTextColor(1, 1, 1)
                else
                    label:SetTextColor(0.5, 0.5, 0.5)
                end
            end
        end
    end

    if compactModeSelector and canChangeProtectedLayout then
        if multipleModes then
            compactModeSelector:Show()
        else
            compactModeSelector:Hide()
        end
        compactModeSelector:SetText(GetModeName(activeMode))
    end
    for _, button in ipairs(compactModeMenuButtons) do
        local mode = button.mode
        if mode and mode ~= activeMode and mode.isKnown() then
            button:Enable()
        else
            button:Disable()
        end
    end
    if compactNameText and compactFrame and canChangeProtectedLayout then
        compactNameText:ClearAllPoints()
        compactNameText:SetPoint("TOPLEFT", compactIcon:GetParent(), "TOPRIGHT", 8, -2)
        if multipleModes and compactModeSelector then
            compactNameText:SetPoint("RIGHT", compactModeSelector, "LEFT", -8, 0)
        else
            compactNameText:SetPoint("RIGHT", compactFrame, "RIGHT", -216, 0)
        end
    end

    if settingsProtectionGroup and settingsModeHint then
        local showProtection = activeMode.usesItemProtection == true
        if showProtection then
            settingsProtectionGroup:Show()
            settingsModeHint:Hide()
        else
            settingsProtectionGroup:Hide()
            settingsModeHint:Show()
        end
    end

    if not multipleModes and compactModeMenu then
        compactModeMenu:Hide()
    end
end

-- Auto-hide the FULL window when combat starts (and keep it closed).
--
-- At combat start we are already in lockdown, so a normal mainFrame:Hide() is a
-- protected operation (the window hosts the secure cast button). The only way to
-- hide it at that moment is from the secure execution environment - a state
-- driver. A stock "visibility" driver would re-SHOW the window when combat ends;
-- we deliberately do NOT want that (Oliver's design: close on pull, STAY closed,
-- reopen via the minimap button = fresh scan). So instead of the visibility
-- driver we register a custom one-way driver whose secure snippet only ever
-- hides - never shows. Out of combat it touches nothing, so manual open/close
-- keep working normally.
--
-- The compact bar is intentionally exempt: it stays visible and usable in
-- combat, so no driver is attached to it.
local mainCombatHideDriverActive = false
local function EnsureMainCombatHideDriver()
    if mainCombatHideDriverActive or not mainFrame then
        return
    end
    -- Very old clients without the secure state-driver API simply run without
    -- the auto-hide (feature-detected, same pattern as elsewhere in the addon).
    if not RegisterStateDriver then
        return
    end
    -- RegisterStateDriver / setting the secure snippet reach into the secure
    -- environment and must never run in combat. If the addon (re)loads mid-combat
    -- via /reload, this is skipped and retried from PLAYER_REGEN_ENABLED once
    -- combat ends.
    if InCombatLockdown() then
        return
    end
    -- mainFrame carries SecureHandlerStateTemplate, so this snippet runs in the
    -- secure environment whenever the "dehcombathide" state changes. On combat
    -- start it hides the window (allowed from secure code even mid-lockdown); on
    -- the way out it does nothing, so the window STAYS closed until reopened.
    mainFrame:SetAttribute("_onstate-dehcombathide", [=[
        if newstate == "combat" then
            self:Hide()
        end
    ]=])
    RegisterStateDriver(mainFrame, "dehcombathide", "[combat] combat; peace")
    mainCombatHideDriverActive = true
end

-- ---------------------------------------------------------------------------
-- Statistics window (1.8): plain text view of ns.Stats.BuildLines
-- ---------------------------------------------------------------------------
local statsFrame
local statsView = "session"

local function RefreshStatsFrame()
    if not (statsFrame and statsFrame:IsShown() and ns.Stats) then
        return
    end
    statsFrame.body:SetText(table.concat(ns.Stats.BuildLines(statsView), "\n"))
    if statsFrame.scrollChild then
        statsFrame.scrollChild:SetHeight(math.max(1,statsFrame.body:GetStringHeight() or 1))
    end
    if statsView == "session" then
        statsFrame.sessionTab:Disable()
        statsFrame.allTab:Enable()
        statsFrame.resetButton:Enable()
    else
        statsFrame.sessionTab:Enable()
        statsFrame.allTab:Disable()
        statsFrame.resetButton:Disable()
    end
end

local function CreateStatsFrame()
    statsFrame = CreateStyledWindow("DisenchantHelper_StatsFrame", 500, 420)
    statsFrame:SetPoint("CENTER", 40, 20)
    statsFrame:Hide()
    statsFrame.title:SetText(L["STATS_TITLE"])

    local sessionTab = CreateFrame("Button", nil, statsFrame, "UIPanelButtonTemplate")
    sessionTab:SetSize(110, 22)
    sessionTab:SetPoint("TOPLEFT", 16, -42)
    sessionTab:SetText(L["STATS_TAB_SESSION"])
    sessionTab:SetScript("OnClick", function()
        statsView = "session"
        RefreshStatsFrame()
    end)
    statsFrame.sessionTab = sessionTab

    local allTab = CreateFrame("Button", nil, statsFrame, "UIPanelButtonTemplate")
    allTab:SetSize(110, 22)
    allTab:SetPoint("LEFT", sessionTab, "RIGHT", 6, 0)
    allTab:SetText(L["STATS_TAB_ALL"])
    allTab:SetScript("OnClick", function()
        statsView = "all"
        RefreshStatsFrame()
    end)
    statsFrame.allTab = allTab

    local resetButton = CreateFrame("Button", nil, statsFrame, "UIPanelButtonTemplate")
    resetButton:SetSize(150, 22)
    resetButton:SetPoint("TOPRIGHT", -16, -42)
    resetButton:SetText(L["STATS_RESET_SESSION"])
    resetButton:SetScript("OnClick", function()
        if ns.Stats then
            ns.Stats.ResetSession()
        end
        RefreshStatsFrame()
    end)
    statsFrame.resetButton = resetButton

    local scroll=CreateFrame("ScrollFrame",nil,statsFrame,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",18,-78);scroll:SetPoint("BOTTOMRIGHT",-32,16)
    local child=CreateFrame("Frame",nil,scroll)
    child:SetSize(440,1);scroll:SetScrollChild(child)
    statsFrame.scrollChild=child
    local body = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT",0,0)
    body:SetWidth(440)
    body:SetWordWrap(true)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    statsFrame.body = body

    statsFrame:SetScript("OnShow", RefreshStatsFrame)
    if ns.Stats then
        -- Live update while the window is open (a new disenchant was recorded).
        ns.Stats.onChange = RefreshStatsFrame
    end
end

local function ToggleStatsFrame()
    if not statsFrame then
        CreateStatsFrame()
    end
    if statsFrame:IsShown() then
        statsFrame:Hide()
    else
        statsFrame:Show()
    end
end

local function CreateMainFrame()
    mainFrame = CreateStyledWindow("DisenchantHelper_MainFrame", 860, 580, "SecureHandlerStateTemplate")
    mainFrame:SetPoint("CENTER")
    mainFrame:Hide()
    mainFrame.RefreshUI = RefreshUI
    mainFrame.title:SetText("Disenchant Helper")

    -- Child windows belong to the main window: closing it closes them too.
    -- This also fires when the combat auto-hide driver closes the window on a
    -- pull, so options/blacklist close alongside it (intended - one clean state).
    mainFrame:SetScript("OnHide", function()
        if blacklistFrame and blacklistFrame:IsShown() then
            blacklistFrame:Hide()
        end
        if settingsFrame and settingsFrame:IsShown() then
            settingsFrame:Hide()
        end
        if statsFrame and statsFrame:IsShown() then
            statsFrame:Hide()
        end
    end)

    -- Arm the combat auto-hide (deferred if we happen to load in combat).
    EnsureMainCombatHideDriver()

    mainSubtitle = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mainSubtitle:SetPoint("TOPLEFT", 16, -38)
    mainSubtitle:SetTextColor(0.7, 0.7, 0.7)
    mainSubtitle:SetText(L[activeMode.subtitleTextKey or "SUBTITLE"] or L["SUBTITLE"])

    CreateModeTabs()
    UpdateModeSurface()

    listPanel = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    listPanel:SetBackdrop(BACKDROP_PANEL)
    listPanel:SetBackdropColor(0, 0, 0, 0.35)
    listPanel:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    local controlsFrame = CreateFrame("Frame", nil, listPanel)
    controlsFrame:SetPoint("BOTTOMLEFT", 8, 8)
    controlsFrame:SetPoint("BOTTOMRIGHT", -8, 8)
    controlsFrame:SetHeight(24)

    listScrollFrame = CreateFrame("ScrollFrame", nil, listPanel, "UIPanelScrollFrameTemplate")
    listScrollFrame:SetPoint("TOPLEFT", 8, -8)
    listScrollFrame:SetPoint("BOTTOMRIGHT", controlsFrame, "TOPRIGHT", -22, 8)

    listScrollChild = CreateFrame("Frame", nil, listScrollFrame)
    listScrollChild:SetSize(1, 1)
    listScrollFrame:SetScrollChild(listScrollChild)

    local refreshButton = CreateFrame("Button", nil, controlsFrame, "UIPanelButtonTemplate")
    refreshButton:SetSize(86, 22)
    refreshButton:SetPoint("RIGHT", controlsFrame, "RIGHT", 0, 0)
    refreshButton:SetText(L["REFRESH"])
    refreshButton:SetScript("OnClick", function()
        RefreshList()
    end)

    local clearButton = CreateFrame("Button", nil, controlsFrame, "UIPanelButtonTemplate")
    clearButton:SetSize(120, 22)
    clearButton:SetPoint("RIGHT", refreshButton, "LEFT", -8, 0)
    clearButton:SetText(L["CLEAR_SELECTION"])
    clearButton:SetScript("OnClick", function()
        wipe(selected)
        BuildQueue()
        RefreshUI()
    end)

    local selectAllButton = CreateFrame("Button", nil, controlsFrame, "UIPanelButtonTemplate")
    selectAllButton:SetSize(110, 22)
    selectAllButton:SetPoint("RIGHT", clearButton, "LEFT", -8, 0)
    selectAllButton:SetText(L["SELECT_ALL"])
    selectAllButton:SetScript("OnClick", function()
        for _, item in ipairs(items) do
            selected[item.key] = true
        end
        BuildQueue()
        RefreshUI()
    end)

    statusText = controlsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("LEFT", controlsFrame, "LEFT", 0, 0)
    statusText:SetPoint("RIGHT", selectAllButton, "LEFT", -8, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetWordWrap(false)

    queuePanel = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    queuePanel:SetBackdrop(BACKDROP_PANEL)
    queuePanel:SetBackdropColor(0, 0, 0, 0.42)
    queuePanel:SetBackdropBorderColor(0.45, 0.35, 0.15, 1)
    queuePanel:Hide()

    local queueTitle = queuePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    queueTitle:SetPoint("TOP", 0, -10)
    queueTitle:SetText(L["QUEUE_TITLE"])

    blacklistOpenButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    blacklistOpenButton:SetSize(128, 22)
    -- Center on the title bar (not on the close button, whose texture
    -- padding makes it sit visually too high)
    blacklistOpenButton:SetPoint("RIGHT", mainFrame.TitleBar, "RIGHT", -26, 0)
    -- No custom strata: the button inherits the main window's layer and only
    -- rises above the title bar within it - so it correctly disappears when
    -- the window sits behind other windows.
    blacklistOpenButton:SetFrameLevel(mainFrame:GetFrameLevel() + 10)
    blacklistOpenButton:SetText(L["OPEN_BLACKLIST"])
    blacklistOpenButton:SetScript("OnClick", function()
        ToggleBlacklistFrame()
    end)

    local compactModeButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    compactModeButton:SetSize(80, 22)
    compactModeButton:SetPoint("RIGHT", blacklistOpenButton, "LEFT", -8, 0)
    compactModeButton:SetFrameLevel(mainFrame:GetFrameLevel() + 10)
    compactModeButton:SetText(L["COMPACT_BUTTON"])
    compactModeButton:SetScript("OnClick", function()
        SetCompactMode(true)
    end)

    local settingsButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    settingsButton:SetSize(80, 22)
    settingsButton:SetPoint("RIGHT", compactModeButton, "LEFT", -8, 0)
    settingsButton:SetFrameLevel(mainFrame:GetFrameLevel() + 10)
    settingsButton:SetText(L["SETTINGS_BUTTON"])
    settingsButton:SetScript("OnClick", function()
        ToggleSettingsFrame()
    end)

    local statsButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    statsButton:SetSize(80, 22)
    statsButton:SetPoint("RIGHT", settingsButton, "LEFT", -8, 0)
    statsButton:SetFrameLevel(mainFrame:GetFrameLevel() + 10)
    statsButton:SetText(L["STATS_BUTTON"])
    statsButton:SetScript("OnClick", function()
        ToggleStatsFrame()
    end)

    queueInfoText = queuePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    queueInfoText:SetPoint("TOPLEFT", 10, -32)
    queueInfoText:SetPoint("TOPRIGHT", -10, -32)
    queueInfoText:SetJustifyH("LEFT")
    queueInfoText:SetText(L["QUEUE_EMPTY"])

    local divider = queuePanel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 0.82, 0, 0.12)
    divider:SetPoint("TOPLEFT", 10, -54)
    divider:SetPoint("TOPRIGHT", -10, -54)
    divider:SetHeight(1)

    queueScrollFrame = CreateFrame("ScrollFrame", nil, queuePanel, "UIPanelScrollFrameTemplate")
    queueScrollFrame:SetPoint("TOPLEFT", 8, -60)
    queueScrollFrame:SetPoint("BOTTOMRIGHT", -30, 46)

    queueScrollChild = CreateFrame("Frame", nil, queueScrollFrame)
    queueScrollChild:SetSize(1, 1)
    queueScrollFrame:SetScrollChild(queueScrollChild)

    queueButton = CreateFrame("Button", QUEUE_BUTTON_NAME, queuePanel, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    queueButton:SetSize(138, 24)
    queueButton:SetPoint("BOTTOMLEFT", queuePanel, "BOTTOMLEFT", 16, 12)
    UpdateQueueButtonClickRegistration()
    queueButton:EnableMouse(true)
    queueButtonText = queueButton:GetFontString()
    if queueButtonText then
        queueButtonText:SetText(L[activeMode.buttonTextKey] or L["DISENCHANT"])
    end
    -- No down-edge guard needed: only ONE click edge is registered (matched to
    -- the cast-on-key-down CVar), so every PreClick call IS the action edge.
    queueButton:SetScript("PreClick", function(self)
        -- Hotkey safety (1.7.0): a key binding can "click" this button even
        -- while it is NOT on screen (main window closed, queue panel hidden).
        -- A mouse click can never come from an invisible button, so this only
        -- affects hotkeys: with nothing visible there is nothing the user can
        -- see being disenchanted, and disenchanting is irreversible - so swallow
        -- the press (the attributes are re-armed on the next refresh).
        if not self:IsVisible() then
            ClearQueueButtonAttributes()
            return
        end

        local now = GetTime()
        -- Debounce: after a cast the bag needs a moment to update and the
        -- button to re-point to the next item; ignore clicks until then.
        if now < (nextAllowedQueueClickAt or 0) then
            ClearQueueButtonAttributes()
            self:Disable()
            UpdateQueueButtonVisual(false, queueButtonText and queueButtonText:GetText() or L[activeMode.buttonTextKey] or L["DISENCHANT"])
            if C_Timer and C_Timer.After then
                C_Timer.After(0.2, function()
                    -- Always re-enable - UpdateQueueButton guards itself.
                    -- (Previously this only ran with the main window open, so
                    -- spamming in compact mode left the button disabled forever.)
                    UpdateQueueButton()
                end)
            end
            return
        end

        if not queue[1] then
            ClearPendingDisenchant()
            return
        end

        -- SAFETY NET: never cast at a stale slot. The armed target-bag/slot
        -- were captured at the last refresh; if the bag shifted since (loot in
        -- combat, item dragged, /deh check rebuilt the queue), the slot may now
        -- hold a DIFFERENT item - and disenchanting is irreversible. Verify the
        -- armed slot still holds queue[1]; if not, swallow this click and re-arm.
        local item = queue[1]
        local armedBag = self:GetAttribute("target-bag")
        local armedSlot = self:GetAttribute("target-slot")
        if not item or item.bag ~= armedBag or item.slot ~= armedSlot
            or GetBagItemLinkSafe(item.bag, item.slot) ~= item.link then
            ClearQueueButtonAttributes()
            self:Disable()
            UpdateQueueButtonVisual(false, L[activeMode.buttonTextKey] or L["DISENCHANT"])
            if C_Timer and C_Timer.After then
                C_Timer.After(0.2, function()
                    RefreshList()
                end)
            end
            return
        end

        if TryBlacklistQueuedItemBeforeCast() then
            ClearQueueButtonAttributes()
            self:Disable()
            UpdateQueueButtonVisual(false, L[activeMode.buttonTextKey] or L["DISENCHANT"])
            if C_Timer and C_Timer.After then
                C_Timer.After(0.2, function()
                    -- Re-enable for the next queue item (blacklisting causes no
                    -- bag event, so nothing else would re-arm the button).
                    UpdateQueueButton()
                end)
            end
            return
        end

        nextAllowedQueueClickAt = now + 0.35
        pendingLootUntil = now + 6
        -- Learning (1.8): snapshot the item NOW (the cast destroys it). Only
        -- here, where the cast really fires - not on the blacklist paths -
        -- and in pcall: statistics must never be able to block a cast.
        if ns.Learn and activeMode and activeMode.key == "disenchant" then
            pcall(ns.Learn.Begin, queue[1], queue[1].manualOnly)
        end
        SetPendingDisenchant(queue[1])
    end)

    manualBlacklistButton = CreateFrame("Button", nil, queuePanel, "UIPanelButtonTemplate")
    manualBlacklistButton:SetSize(138, 22)
    manualBlacklistButton:SetPoint("BOTTOMLEFT", queuePanel, "BOTTOMLEFT", 162, 13)
    manualBlacklistButton:SetText(L["BLACKLIST_ITEM_BUTTON"])
    manualBlacklistButton:SetScript("OnClick", function()
        local item = queue and queue[1]
        if not item then
            Print(L["NO_QUEUE_ITEM"])
            return
        end
        AddItemToBlacklist(item, L["ADDED_MANUAL"])
    end)

    listPanel:SetScript("OnSizeChanged", function()
        UpdateListRows()
    end)

    queuePanel:SetScript("OnSizeChanged", function()
        UpdateQueueRows()
    end)

    blacklistFrame = CreateStyledWindow("DisenchantHelper_BlacklistFrame", 500, 420)
    blacklistFrame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    blacklistFrame:Hide()
    blacklistFrame:SetScript("OnShow", function(self)
        RaiseAddonWindows(self)
    end)
    blacklistFrame.title:SetText(L["BLACKLIST_TITLE"])

    local blacklistSubtitle = blacklistFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    blacklistSubtitle:SetPoint("TOPLEFT", 16, -38)
    blacklistSubtitle:SetTextColor(0.7, 0.7, 0.7)
    blacklistSubtitle:SetText(L["BLACKLIST_SUBTITLE"])

    blacklistScrollFrame = CreateFrame("ScrollFrame", nil, blacklistFrame, "UIPanelScrollFrameTemplate")
    blacklistScrollFrame:SetPoint("TOPLEFT", 12, -56)
    blacklistScrollFrame:SetPoint("BOTTOMRIGHT", -30, 44)

    blacklistScrollChild = CreateFrame("Frame", nil, blacklistScrollFrame)
    blacklistScrollChild:SetSize(1, 1)
    blacklistScrollFrame:SetScrollChild(blacklistScrollChild)

    blacklistEmptyText = blacklistFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    blacklistEmptyText:SetPoint("TOPLEFT", blacklistScrollFrame, "TOPLEFT", 4, -4)
    blacklistEmptyText:SetText(L["BLACKLIST_EMPTY"])

    local clearBlacklistButton = CreateFrame("Button", nil, blacklistFrame, "UIPanelButtonTemplate")
    clearBlacklistButton:SetSize(110, 22)
    clearBlacklistButton:SetPoint("BOTTOMRIGHT", blacklistFrame, "BOTTOMRIGHT", -12, 12)
    clearBlacklistButton:SetText(L["CLEAR_ALL"])
    clearBlacklistButton:SetScript("OnClick", function()
        wipe(GetModeBlacklist())
        Print(L["BLACKLIST_CLEARED"])
        RefreshBlacklistUI()
        RefreshList()
    end)
end

local function CreateMinimapButton()
    -- LibStub hands out the libraries from the Libs folder (true = fail
    -- silently; if they are missing the addon simply runs without a button)
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    libDBIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
    if not LDB or not libDBIcon then
        return
    end

    -- Registered as an LDB launcher instead of a hand-built button so that
    -- collectors (ElvUI, MBB, Blizzard's addon compartment) can manage it
    local dataObject = LDB:NewDataObject("DisenchantHelper", {
        type = "launcher",
        text = "Disenchant Helper",
        icon = GetSpellTextureSafe(SPELL_ID_DISENCHANT) or 136244,
        OnClick = function(_, button)
            if button == "LeftButton" then
                ToggleMainFrame()
            elseif button == "RightButton" then
                ToggleSettingsFrame()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Disenchant Helper")
            tooltip:AddLine(L["MM_LEFT"], 1, 1, 1)
            tooltip:AddLine(L["MM_RIGHT"], 1, 1, 1)
            tooltip:AddLine(L["MM_DRAG"], 1, 1, 1)
            tooltip:AddLine(L["MM_COMPACT_HINT"], 0.6, 0.8, 1)
        end,
    })

    -- LibDBIcon renders the button and manages position/drag/visibility
    -- on its own inside db.minimap
    libDBIcon:Register("DisenchantHelper", dataObject, db.minimap)
end

local function CreateCompactFrame()
    compactFrame = CreateFrame("Frame", "DisenchantHelper_CompactFrame", UIParent, "BackdropTemplate")
    compactFrame:SetSize(400, 58)
    if db.compactPoint then
        compactFrame:SetPoint(db.compactPoint.point or "CENTER", UIParent, db.compactPoint.relPoint or "CENTER", db.compactPoint.x or 0, db.compactPoint.y or 0)
    else
        compactFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    end
    compactFrame:SetBackdrop(BACKDROP_PANEL)
    compactFrame:SetBackdropColor(0, 0, 0, 0.55)
    compactFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    compactFrame:SetMovable(true)
    compactFrame:EnableMouse(true)
    compactFrame:RegisterForDrag("LeftButton")
    compactFrame:SetClampedToScreen(true)
    compactFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    compactFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        db.compactPoint = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    compactFrame:Hide()

    local closeButton = CreateFrame("Button", nil, compactFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", 2, 2)
    closeButton:SetScale(0.7)
    closeButton:SetScript("OnClick", function()
        -- Same combat rule as the styled windows: the bar hosts the secure
        -- button in compact mode, so hiding it is protected in combat.
        if InCombatLockdown() and compactFrame:IsProtected() then
            Print(L["NOT_IN_COMBAT"])
            return
        end
        compactFrame:Hide()
    end)

    local iconBorder = CreateIconBorder(compactFrame, 34)
    iconBorder:SetPoint("TOPLEFT", 12, -12)

    compactIcon = iconBorder:CreateTexture(nil, "ARTWORK")
    compactIcon:SetPoint("TOPLEFT", 2, -2)
    compactIcon:SetPoint("BOTTOMRIGHT", -2, 2)

    iconBorder:EnableMouse(true)
    iconBorder:SetScript("OnEnter", function(self)
        local item = compactFrame and compactFrame.currentItem
        if not item then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetBagItem(item.bag, item.slot)
        if ns.Prediction and activeMode and activeMode.key == "disenchant" and db and db.showExpected ~= false then
            ns.Prediction.AppendToTooltip(GameTooltip, item)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L[activeMode.blacklistHintKey or "COMPACT_BLACKLIST_HINT"] or L["COMPACT_BLACKLIST_HINT"], 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    iconBorder:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    iconBorder:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton ~= "RightButton" then
            return
        end
        local item = compactFrame and compactFrame.currentItem
        if not item then
            return
        end
        GameTooltip:Hide()
        AddItemToBlacklist(item, L["ADDED_MANUAL"])
    end)

    compactFullButton = CreateFrame("Button", nil, compactFrame, "UIPanelButtonTemplate")
    compactFullButton:SetSize(48, 20)
    compactFullButton:SetPoint("TOPRIGHT", compactFrame, "TOPRIGHT", -24, -18)
    compactFullButton:SetText(L["FULL_BUTTON"])
    compactFullButton:SetScript("OnClick", function()
        SetCompactMode(false)
    end)

    compactModeSelector = CreateFrame("Button", nil, compactFrame, "UIPanelButtonTemplate")
    compactModeSelector:SetSize(90, 20)
    compactModeSelector:SetPoint("TOPRIGHT", compactFrame, "TOPRIGHT", -214, -18)
    compactModeSelector:SetScript("OnClick", function()
        if InCombatLockdown() then
            Print(L["MODE_CHANGE_IN_COMBAT"] or L["NOT_IN_COMBAT"])
            return
        end
        if compactModeMenu:IsShown() then
            compactModeMenu:Hide()
        else
            compactModeMenu:Show()
            compactModeMenu:Raise()
        end
    end)
    compactModeSelector:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["MODE_SWITCH_HINT"], 0.7, 0.8, 1, true)
        GameTooltip:Show()
    end)
    compactModeSelector:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    CreateCompactModeMenu()
    compactModeMenu:SetPoint("BOTTOMRIGHT", compactModeSelector, "TOPRIGHT", 0, 6)

    compactNameText = compactFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    compactNameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 8, -2)
    compactNameText:SetPoint("RIGHT", compactFrame, "RIGHT", -216, 0)
    compactNameText:SetJustifyH("LEFT")
    compactNameText:SetWordWrap(false)

    compactQueueText = compactFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    compactQueueText:SetPoint("BOTTOMLEFT", iconBorder, "BOTTOMRIGHT", 8, 2)
    compactQueueText:SetPoint("RIGHT", compactNameText, "RIGHT", 0, 0)
    compactQueueText:SetJustifyH("LEFT")
    compactQueueText:SetTextColor(0.75, 0.75, 0.75)

    compactPreviewText = compactFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    compactPreviewText:SetPoint("BOTTOMLEFT", compactFrame, "BOTTOMLEFT", 14, 8)
    compactPreviewText:SetPoint("RIGHT", compactFrame, "RIGHT", -14, 0)
    compactPreviewText:SetJustifyH("LEFT")
    compactPreviewText:SetWordWrap(false)
    compactPreviewText:SetTextColor(0.75, 0.8, 0.9)

    compactFrame:HookScript("OnHide", function()
        if compactModeMenu then
            compactModeMenu:Hide()
        end
    end)
    UpdateModeSurface()
end

-- ---------------------------------------------------------------------------
-- Hotkey (1.7.0)
-- The real binding lives in the client's own binding system (CLICK binding on
-- the queue button, see Bindings.xml): it is saved per the user's binding set,
-- listed under Options > Key Bindings > Disenchant Helper and conflict-checked by the
-- client. The settings window only offers a shortcut to set/clear it there.
-- ---------------------------------------------------------------------------
local hotkeyButton
local hotkeyClearButton
local hotkeyCapturing = false

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true,
}

local function CanEditBindings()
    return type(SetBinding) == "function" and type(GetBindingKey) == "function"
        and (type(SaveBindings) == "function" or type(AttemptToSaveBindings) == "function")
        and type(GetCurrentBindingSet) == "function"
end

local function SaveBindingChanges()
    local save = SaveBindings or AttemptToSaveBindings
    if save and GetCurrentBindingSet then
        save(GetCurrentBindingSet())
        return true
    end
    return false
end

local function FormatBindingKey(key)
    if GetBindingText then
        return GetBindingText(key, "KEY_") or key
    end
    return key
end

local function RefreshHotkeyDisplay()
    if not hotkeyButton or hotkeyCapturing then
        return
    end
    local key1, key2 = nil, nil
    if GetBindingKey then
        key1, key2 = GetBindingKey(QUEUE_BINDING)
    end
    if key1 then
        local text = FormatBindingKey(key1)
        if key2 then
            text = text .. ", " .. FormatBindingKey(key2)
        end
        hotkeyButton:SetText(text)
        hotkeyClearButton:Enable()
    else
        hotkeyButton:SetText(L["HOTKEY_NOT_BOUND"])
        hotkeyClearButton:Disable()
    end
end

local function StopHotkeyCapture()
    hotkeyCapturing = false
    if hotkeyButton then
        hotkeyButton:EnableKeyboard(false)
    end
    RefreshHotkeyDisplay()
end

local function ApplyHotkey(binding)
    if InCombatLockdown() then
        Print(L["HOTKEY_IN_COMBAT"])
        return
    end

    -- The client would silently steal the key from its previous owner;
    -- tell the user what they just overwrote.
    local existing = GetBindingAction and GetBindingAction(binding)
    if existing and existing ~= "" and existing ~= QUEUE_BINDING then
        local actionName = (GetBindingName and GetBindingName(existing)) or existing
        Print(string.format(L["HOTKEY_REPLACED"], FormatBindingKey(binding), tostring(actionName)))
    end

    -- Keep exactly one key: drop whatever this action had before.
    local old1, old2 = GetBindingKey(QUEUE_BINDING)
    if old1 and old1 ~= binding then
        SetBinding(old1)
    end
    if old2 and old2 ~= binding then
        SetBinding(old2)
    end

    SetBinding(binding, QUEUE_BINDING)
    if SaveBindingChanges() then
        Print(string.format(L["HOTKEY_SET"], FormatBindingKey(binding)))
    else
        Print(L["HOTKEY_NOT_SAVED"])
    end
end

local function ClearHotkey()
    if InCombatLockdown() then
        Print(L["HOTKEY_IN_COMBAT"])
        return
    end
    local key1, key2 = GetBindingKey(QUEUE_BINDING)
    if key1 then
        SetBinding(key1)
    end
    if key2 then
        SetBinding(key2)
    end
    SaveBindingChanges()
    RefreshHotkeyDisplay()
end

local function StartHotkeyCapture()
    if InCombatLockdown() then
        Print(L["HOTKEY_IN_COMBAT"])
        return
    end
    hotkeyCapturing = true
    hotkeyButton:SetText(L["HOTKEY_PRESS"])
    hotkeyButton:EnableKeyboard(true)
end

local function CreateSettingsFrame()
    settingsFrame = CreateStyledWindow("DisenchantHelper_SettingsFrame", 470, 655)
    settingsFrame:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
    settingsFrame:Hide()
    settingsFrame.title:SetText(L["SETTINGS_TITLE"])

    -- Hotkey section (top). Not part of the protection group: it applies to
    -- every processing mode, while the group below is hidden for modes without
    -- item protection. The group is shifted down to make room.
    local hotkeyHeader = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hotkeyHeader:SetPoint("TOPLEFT", 14, -42)
    hotkeyHeader:SetText(L["HOTKEY_HEADER"])

    hotkeyButton = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    hotkeyButton:SetSize(170, 24)
    hotkeyButton:SetPoint("TOPLEFT", 24, -62)

    hotkeyClearButton = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    hotkeyClearButton:SetSize(80, 24)
    hotkeyClearButton:SetPoint("LEFT", hotkeyButton, "RIGHT", 8, 0)
    hotkeyClearButton:SetText(L["HOTKEY_CLEAR"])

    local hotkeyHint = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hotkeyHint:SetPoint("TOPLEFT", 24, -90)
    hotkeyHint:SetPoint("RIGHT", settingsFrame, "RIGHT", -16, 0)
    hotkeyHint:SetJustifyH("LEFT")
    hotkeyHint:SetWordWrap(true)

    local hotkeyDivider = settingsFrame:CreateTexture(nil, "ARTWORK")
    hotkeyDivider:SetColorTexture(0.4, 0.4, 0.4, 0.4)
    hotkeyDivider:SetPoint("TOPLEFT", 14, -122)
    hotkeyDivider:SetPoint("TOPRIGHT", -14, -122)
    hotkeyDivider:SetHeight(1)

    if CanEditBindings() then
        hotkeyHint:SetText(L["HOTKEY_HINT"])
        hotkeyButton:RegisterForClicks("LeftButtonUp")
        hotkeyButton:SetScript("OnClick", function()
            if hotkeyCapturing then
                StopHotkeyCapture()
            else
                StartHotkeyCapture()
            end
        end)
        hotkeyButton:SetScript("OnKeyDown", function(self, key)
            if not hotkeyCapturing then
                return
            end
            if MODIFIER_KEYS[key] then
                return -- wait for the actual key; modifiers are read from the keyboard state
            end
            if key == "ESCAPE" then
                StopHotkeyCapture()
                return
            end
            local binding = key
            if IsShiftKeyDown() then binding = "SHIFT-" .. binding end
            if IsControlKeyDown() then binding = "CTRL-" .. binding end
            if IsAltKeyDown() then binding = "ALT-" .. binding end
            StopHotkeyCapture()
            ApplyHotkey(binding)
            RefreshHotkeyDisplay()
        end)
        hotkeyButton:SetScript("OnHide", StopHotkeyCapture)
        hotkeyClearButton:SetScript("OnClick", ClearHotkey)
    else
        -- A client without the binding API: fall back to the standard menu.
        hotkeyHint:SetText(L["HOTKEY_HINT_MENU_ONLY"])
        hotkeyButton:Disable()
        hotkeyClearButton:Disable()
    end
    RefreshHotkeyDisplay()

    settingsProtectionGroup = CreateFrame("Frame", nil, settingsFrame)
    settingsProtectionGroup:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 0, -92)
    settingsProtectionGroup:SetPoint("BOTTOMRIGHT", settingsFrame, "BOTTOMRIGHT", 0, 0)

    settingsModeHint = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settingsModeHint:SetPoint("TOPLEFT", 24, -142)
    settingsModeHint:SetPoint("RIGHT", settingsFrame, "RIGHT", -24, 0)
    settingsModeHint:SetJustifyH("LEFT")
    settingsModeHint:SetWordWrap(true)
    settingsModeHint:SetText(L["MODE_NO_PROTECTION_SETTINGS"])
    settingsModeHint:Hide()
    -- Item level protection ---------------------------------------------
    local ilvlCheckbox = CreateFrame("CheckButton", nil, settingsProtectionGroup, "UICheckButtonTemplate")
    ilvlCheckbox:SetSize(26, 26)
    ilvlCheckbox:SetPoint("TOPLEFT", 14, -42)

    local ilvlLabel = settingsProtectionGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ilvlLabel:SetPoint("LEFT", ilvlCheckbox, "RIGHT", 4, 0)
    ilvlLabel:SetText(L["ILVL_PROTECT"])

    local belowLabel = settingsProtectionGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    belowLabel:SetPoint("TOPLEFT", 44, -80)
    belowLabel:SetText(L["ILVL_BELOW"])

    local ilvlEditBox = CreateFrame("EditBox", nil, settingsProtectionGroup, "InputBoxTemplate")
    ilvlEditBox:SetSize(52, 20)
    ilvlEditBox:SetPoint("LEFT", belowLabel, "RIGHT", 14, 0)
    ilvlEditBox:SetAutoFocus(false)
    ilvlEditBox:SetNumeric(true)
    ilvlEditBox:SetMaxLetters(4)

    local suggestButton = CreateFrame("Button", nil, settingsProtectionGroup, "UIPanelButtonTemplate")
    suggestButton:SetSize(90, 22)
    -- Pinned to the window's right edge (not chained off the edit box) so a longer
    -- localized label can never push it past the frame border. The wider window
    -- (470) keeps a clear gap between the edit box and the button.
    suggestButton:SetPoint("TOPRIGHT", settingsProtectionGroup, "TOPRIGHT", -14, -75)
    suggestButton:SetText(L["ILVL_SUGGEST"])

    local ilvlHint = settingsProtectionGroup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ilvlHint:SetPoint("TOPLEFT", 44, -108)
    ilvlHint:SetPoint("RIGHT", settingsFrame, "RIGHT", -16, 0)
    ilvlHint:SetJustifyH("LEFT")
    ilvlHint:SetWordWrap(true)
    ilvlHint:SetText(L["ILVL_HINT"])

    local ilvlDivider = settingsProtectionGroup:CreateTexture(nil, "ARTWORK")
    ilvlDivider:SetColorTexture(0.4, 0.4, 0.4, 0.4)
    ilvlDivider:SetPoint("TOPLEFT", 14, -162)
    ilvlDivider:SetPoint("TOPRIGHT", -14, -162)
    ilvlDivider:SetHeight(1)

    -- Market value protection -------------------------------------------
    local priceCheckbox = CreateFrame("CheckButton", nil, settingsProtectionGroup, "UICheckButtonTemplate")
    priceCheckbox:SetSize(26, 26)
    priceCheckbox:SetPoint("TOPLEFT", 14, -174)

    local priceLabel = settingsProtectionGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    priceLabel:SetPoint("LEFT", priceCheckbox, "RIGHT", 4, 0)
    priceLabel:SetText(L["PRICE_PROTECT"])

    local priceAtLeastLabel = settingsProtectionGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceAtLeastLabel:SetPoint("TOPLEFT", 44, -212)
    priceAtLeastLabel:SetText(L["PRICE_AT_LEAST"])

    local priceEditBox = CreateFrame("EditBox", nil, settingsProtectionGroup, "InputBoxTemplate")
    priceEditBox:SetSize(76, 20)
    priceEditBox:SetPoint("LEFT", priceAtLeastLabel, "RIGHT", 10, 0)
    priceEditBox:SetAutoFocus(false)
    priceEditBox:SetNumeric(true)
    priceEditBox:SetMaxLetters(9)

    local priceGoldLabel = settingsProtectionGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceGoldLabel:SetPoint("LEFT", priceEditBox, "RIGHT", 8, 0)
    priceGoldLabel:SetText(L["PRICE_GOLD"])

    local priceHint = settingsProtectionGroup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    priceHint:SetPoint("TOPLEFT", 44, -240)
    priceHint:SetPoint("RIGHT", settingsFrame, "RIGHT", -16, 0)
    priceHint:SetJustifyH("LEFT")
    priceHint:SetWordWrap(true)
    priceHint:SetText(L["PRICE_HINT"])

    local priceDivider = settingsProtectionGroup:CreateTexture(nil, "ARTWORK")
    priceDivider:SetColorTexture(0.4, 0.4, 0.4, 0.4)
    priceDivider:SetPoint("TOPLEFT", 14, -300)
    priceDivider:SetPoint("TOPRIGHT", -14, -300)
    priceDivider:SetHeight(1)

    -- Quality filter -----------------------------------------------------
    local qualityHeader = settingsProtectionGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qualityHeader:SetPoint("TOPLEFT", 14, -312)
    qualityHeader:SetText(L["QUALITY_HEADER"])

    local qualityChecks = {}
    local yOffset = -338
    for _, quality in ipairs({ UNCOMMON_QUALITY, RARE_QUALITY, EPIC_QUALITY }) do
        local check = CreateFrame("CheckButton", nil, settingsProtectionGroup, "UICheckButtonTemplate")
        check:SetSize(26, 26)
        check:SetPoint("TOPLEFT", 24, yOffset)

        local label = settingsProtectionGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", check, "RIGHT", 4, 0)
        label:SetText(L["QUALITY_" .. quality] or tostring(quality))
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if color then
            label:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
        end

        check:SetScript("OnClick", function(self)
            db.qualityFilter[quality] = self:GetChecked() and true or false
            RefreshList()
        end)

        qualityChecks[quality] = check
        yOffset = yOffset - 30
    end

    -- Preview settings are independent of disenchant queue protection.
    local previewHeader=settingsFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    previewHeader:SetPoint("TOPLEFT",18,-540)
    previewHeader:SetText(L["PREVIEW_SETTINGS"])
    local helperPreview=CreateFrame("CheckButton",nil,settingsFrame,"UICheckButtonTemplate")
    helperPreview:SetSize(26,26);helperPreview:SetPoint("TOPLEFT",14,-562)
    settingsFrame.helperPreview=helperPreview
    local helperLabel=settingsFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    helperLabel:SetPoint("LEFT",helperPreview,"RIGHT",4,0)
    helperLabel:SetText(L["PREVIEW_HELPER"])
    helperPreview:SetScript("OnClick",function(self)
        db.showExpected=self:GetChecked() and true or false
        RefreshUI()
    end)
    local externalPreview=CreateFrame("CheckButton",nil,settingsFrame,"UICheckButtonTemplate")
    externalPreview:SetSize(26,26);externalPreview:SetPoint("TOPLEFT",14,-590)
    settingsFrame.externalPreview=externalPreview
    local externalLabel=settingsFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    externalLabel:SetPoint("LEFT",externalPreview,"RIGHT",4,0)
    externalLabel:SetText(L["PREVIEW_EXTERNAL"])
    externalPreview:SetScript("OnClick",function(self)
        db.externalItemTooltips=self:GetChecked() and true or false
    end)
    local previewHint=settingsFrame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    previewHint:SetPoint("TOPLEFT",44,-620);previewHint:SetWidth(402)
    previewHint:SetWordWrap(true);previewHint:SetText(L["PREVIEW_EXTERNAL_HINT"])

    -- Behavior -----------------------------------------------------------
    -- Enabled protection with an empty threshold silently protects nothing.
    -- Warn from either control so this safety gap can never go unnoticed.
    local function WarnIfCapEmpty()
        if db.ilvlCapEnabled and not tonumber(db.ilvlCap) then
            Print(L["ILVL_CAP_EMPTY"])
        end
    end

    local function ApplyIlvlCap()
        db.ilvlCap = tonumber(ilvlEditBox:GetText())
        WarnIfCapEmpty()
        RefreshList()
    end

    ilvlCheckbox:SetScript("OnClick", function(self)
        db.ilvlCapEnabled = self:GetChecked() and true or false
        WarnIfCapEmpty()
        RefreshList()
    end)

    ilvlEditBox:SetScript("OnEnterPressed", function(self)
        ApplyIlvlCap()
        self:ClearFocus()
    end)
    ilvlEditBox:SetScript("OnEditFocusLost", ApplyIlvlCap)
    ilvlEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local function WarnIfPriceThresholdEmpty()
        if db.priceWarnEnabled and not tonumber(db.priceThresholdGold) then
            Print(L["PRICE_THRESHOLD_EMPTY"])
        end
    end

    local function ApplyPriceThreshold()
        db.priceThresholdGold = tonumber(priceEditBox:GetText())
        WarnIfPriceThresholdEmpty()
        RefreshList()
    end

    priceCheckbox:SetScript("OnClick", function(self)
        db.priceWarnEnabled = self:GetChecked() and true or false
        WarnIfPriceThresholdEmpty()
        RefreshList()
    end)

    priceEditBox:SetScript("OnEnterPressed", function(self)
        ApplyPriceThreshold()
        self:ClearFocus()
    end)
    priceEditBox:SetScript("OnEditFocusLost", ApplyPriceThreshold)
    priceEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    suggestButton:SetScript("OnClick", function()
        local lowest = GetLowestEquippedItemLevel()
        if lowest then
            ilvlEditBox:SetText(tostring(lowest))
            ApplyIlvlCap()
        end
    end)

    settingsFrame:SetScript("OnShow", function()
        UpdateModeSurface()
        helperPreview:SetChecked(db.showExpected~=false)
        externalPreview:SetChecked(db.externalItemTooltips==true)
        RefreshHotkeyDisplay()
        ilvlCheckbox:SetChecked(db.ilvlCapEnabled and true or false)
        ilvlEditBox:SetText(db.ilvlCap and tostring(db.ilvlCap) or "")
        priceCheckbox:SetChecked(db.priceWarnEnabled and true or false)
        priceEditBox:SetText(db.priceThresholdGold and tostring(db.priceThresholdGold) or "")
        for quality, check in pairs(qualityChecks) do
            check:SetChecked(db.qualityFilter[quality] ~= false)
        end
    end)
end
ToggleSettingsFrame = function()
    if not settingsFrame then
        return
    end

    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        settingsFrame:ClearAllPoints()
        if mainFrame and mainFrame:IsShown() then
            settingsFrame:SetPoint("TOPRIGHT", mainFrame, "TOPLEFT", -20, -12)
        else
            settingsFrame:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
        end
        settingsFrame:Show()
        settingsFrame:Raise()
    end
end

-- Self-diagnostic (/deh check): quick smoke test after installs and the
-- first thing to ask users for in bug reports. Output is English on purpose
-- so pasted reports are readable regardless of the user's locale.
-- Copy-paste window for /deh check output (plain text, no color codes) so
-- users can select-all + copy it straight into a bug report.
local checkCopyFrame
local function ShowCheckCopyWindow(text)
    if not checkCopyFrame then
        checkCopyFrame = CreateStyledWindow("DisenchantHelper_CheckFrame", 500, 420)
        checkCopyFrame:SetPoint("CENTER")
        checkCopyFrame:SetFrameStrata("DIALOG")
        checkCopyFrame.title:SetText(L["CHECK_TITLE"])

        local hint = checkCopyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", 16, -40)
        hint:SetPoint("RIGHT", checkCopyFrame, "RIGHT", -16, 0)
        hint:SetJustifyH("LEFT")
        hint:SetTextColor(0.7, 0.7, 0.7)
        hint:SetText(L["CHECK_COPY_HINT"])

        local scroll = CreateFrame("ScrollFrame", "DisenchantHelper_CheckScroll", checkCopyFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -62)
        scroll:SetPoint("BOTTOMRIGHT", -32, 14)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetAutoFocus(false)
        edit:EnableMouse(true)
        edit:SetWidth(440)
        edit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            checkCopyFrame:Hide()
        end)
        scroll:SetScrollChild(edit)
        checkCopyFrame.edit = edit
    end

    checkCopyFrame.edit:SetText(text)
    checkCopyFrame:Show()
    checkCopyFrame:Raise()
    checkCopyFrame.edit:HighlightText()
    checkCopyFrame.edit:SetFocus()
end

local function RunSelfCheck(forceWindow)
    local lines = {}
    local anyFail = false
    local function report(ok, label, detail)
        if not ok then
            anyFail = true
        end
        local suffix = detail and (" - " .. tostring(detail)) or ""
        lines[#lines + 1] = string.format("[%s] %s%s", ok and "OK" or "FAIL", label, suffix)
        local state = ok and "|cff00ff00OK|r" or "|cffff4040FAIL|r"
        Print(string.format("[%s] %s%s", state, label, suffix))
    end

    local meta
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        meta = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
    elseif GetAddOnMetadata then
        meta = GetAddOnMetadata(ADDON_NAME, "Version")
    end
    local header = "Disenchant Helper self-check (version " .. (meta or "?") .. ")"
    lines[#lines + 1] = header
    Print("--- " .. header .. " ---")

    local gameVersion, build, _, tocVersion = GetBuildInfo()
    report(true, "Client", gameVersion .. " (build " .. build .. ", interface " .. tostring(tocVersion) .. ")")
    -- Check for actual CONTENT, not just existence: the main file guarantees
    -- an (empty) table either way, so "L exists" would still look OK even if
    -- Locales.lua never loaded - exactly the bug a missing .toc line causes.
    report(L ~= nil and L["DISENCHANT"] ~= nil, "Locale table", GetLocale())

    -- Libraries
    report(LibStub ~= nil, "LibStub")
    local ldb = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    report(ldb ~= nil, "LibDataBroker-1.1")
    report(libDBIcon ~= nil, "LibDBIcon-1.0", libDBIcon and "minimap button registered" or "button unavailable")

    -- Active API paths (shows which fallbacks this client uses)
    report(C_Container and C_Container.GetContainerItemInfo ~= nil, "C_Container API")
    report((C_Item and C_Item.IsEquippableItem) ~= nil or IsEquippableItem ~= nil, "Equippable check",
        (C_Item and C_Item.IsEquippableItem) and "modern" or "legacy fallback")
    report(true, "Item GUID keys",
        (C_Item and C_Item.GetItemGUID) and "GUID" or "bag:slot fallback")
    report(true, "Bags scanned", tostring(#BAGS_TO_SCAN) .. (REAGENT_BAG and " (incl. reagent bag)" or " (no reagent bag)"))

    -- Saved variables & settings
    report(type(db) == "table", "SavedVariables")
    if type(db) == "table" then
        local blacklistCount = 0
        if type(db.blacklist) == "table" then
            for _ in pairs(GetModeBlacklist()) do
                blacklistCount = blacklistCount + 1
            end
        end
        report(true, "Settings", string.format("ilvl cap %s (%s), blacklist %d, compact %s",
            db.ilvlCapEnabled and "on" or "off", tostring(db.ilvlCap or "-"),
            blacklistCount, db.compactMode and "on" or "off"))
    end

    -- Frames
    report(mainFrame ~= nil, "Main window")
    report(compactFrame ~= nil, "Compact bar")
    report(settingsFrame ~= nil, "Settings window")
    report(blacklistFrame ~= nil, "Blacklist window")

    -- Value guard / price providers (v1.5.0). Only a FAIL when the guard is on
    -- but no price addon answers - then the feature would silently do nothing.
    if ns.Prices and ns.Prices.GetProviderStatus then
        local available = {}
        for _, p in ipairs(ns.Prices.GetProviderStatus()) do
            if p.available then
                available[#available + 1] = p.label
            end
        end
        local found = #available > 0 and table.concat(available, ", ") or "none"
        if db and db.priceWarnEnabled then
            report(#available > 0, "Price providers",
                (#available > 0) and (found .. ", threshold " .. tostring(db.priceThresholdGold or "-") .. "g")
                or "value guard ON but no price addon found")
        else
            report(true, "Price providers", found .. " (guard off)")
        end
    end

    -- Every visible mode must resolve a spell name because the secure button
    -- casts by name. Reporting the active key makes cross-client bug reports
    -- useful once milling/prospecting join the descriptor list.
    local availableModes = GetAvailableModes()
    local availableKeys = {}
    for _, mode in ipairs(availableModes) do
        availableKeys[#availableKeys + 1] = mode.key
        report(mode.spellName() ~= nil, "Mode " .. mode.key .. " spell lookup")
    end
    report(#availableModes > 0, "Processing modes",
        table.concat(availableKeys, ", ") .. "; active " .. tostring(activeMode and activeMode.key or "?"))

    if queueButton then
        local expectedEdge = (GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")) and "AnyDown" or "AnyUp"
        report(queueButton.dehClickEdge == expectedEdge, "Click edge matches CVar", expectedEdge)
    end

    -- Hotkey (1.7.0): the queue button must carry its global name, otherwise
    -- the CLICK binding from Bindings.xml has nothing to target.
    if queueButton then
        report(queueButton:GetName() == QUEUE_BUTTON_NAME, "Queue button bindable", QUEUE_BUTTON_NAME)
        local hk1, hk2 = nil, nil
        if GetBindingKey then
            hk1, hk2 = GetBindingKey(QUEUE_BINDING)
        end
        report(true, "Hotkey", hk1 and (FormatBindingKey(hk1) .. (hk2 and (", " .. FormatBindingKey(hk2)) or "")) or "not bound")
    end

    -- Live scan smoke test
    report(activeMode and activeMode.isKnown(), "Active mode known on this character", activeMode and activeMode.key or "?")
    if not InCombatLockdown() then
        ScanBags()
        -- Re-arm after the scan: ScanBags rebuilt the queue, so without this
        -- the secure attributes would lag one refresh behind - the check would
        -- compare fresh queue against stale attributes (and leave them stale).
        UpdateQueueButton()
        report(true, "Bag scan", string.format("%d item(s) listed, %d in queue", #items, #queue))
        if queue[1] and queueButton then
            report(queueButton:GetAttribute("type") == "spell"
                and queueButton:GetAttribute("target-bag") == queue[1].bag
                and queueButton:GetAttribute("target-slot") == queue[1].slot,
                "Cast button armed",
                "next: " .. (queue[1].name or "?"))
        else
            report(true, "Cast button", "idle (queue empty)")
        end
    else
        report(false, "Bag scan", "skipped (in combat)")
    end

    lines[#lines + 1] = "--- end ---"
    Print("--- End of self-check ---")

    if anyFail or forceWindow then
        ShowCheckCopyWindow(table.concat(lines, "\n"))
    else
        Print(L["CHECK_ALL_OK"])
    end
end

SLASH_DISENCHANTHELPER1 = "/rde"
SLASH_DISENCHANTHELPER2 = "/deh"
-- Prints the command overview. Lives in its own function so both "/deh help"
-- and any unknown command can share it - before this, a typo like "/deh hilfe"
-- silently toggled the main window, which read as "the command did nothing".
local function PrintHelp()
    Print(L["HELP_HEADER"])
    Print("  /deh mail - " .. L["HELP_MAIL"])
    Print("  /deh - " .. L["HELP_TOGGLE"])
    Print("  /deh compact - " .. L["HELP_COMPACT"])
    Print("  /deh options - " .. L["HELP_OPTIONS"])
    Print("  /deh show | hide | reset - " .. L["HELP_MINIMAP"])
    Print("  /deh refresh - " .. L["HELP_REFRESH"])
    Print("  /deh clearblacklist - " .. L["HELP_CLEARBLACKLIST"])
    Print("  /deh check - " .. L["HELP_CHECK"])
    Print("  /deh copy - " .. L["HELP_COPY"])
    Print("  /deh de [all | copy | reset] - " .. L["HELP_LEARN"])
    Print("  /deh ev [on | off] - " .. L["HELP_EV"])
    Print("  /deh stats [reset | resetall] - " .. L["HELP_STATS"])
end

SlashCmdList.DISENCHANTHELPER = function(msg)
    msg = string.lower(strtrim(msg or ""))

    -- All branches below touch db (settings, blacklist, minimap state);
    -- one guard here beats scattered "db and ..." checks in every branch.
    if not db then
        return
    end

    if msg == "show" then
        db.minimap.hide = false
        if libDBIcon then
            libDBIcon:Show("DisenchantHelper")
        end
        Print(L["MM_SHOWN"])
        return
    elseif msg == "hide" then
        db.minimap.hide = true
        if libDBIcon then
            libDBIcon:Hide("DisenchantHelper")
        end
        Print(L["MM_HIDDEN"])
        return
    elseif msg == "refresh" then
        RefreshList()
        Print(L["LIST_REFRESHED"])
        return
    elseif msg == "resetbutton" or msg == "reset" then
        db.minimap.hide = false
        db.minimap.minimapPos = 220
        if libDBIcon then
            libDBIcon:Refresh("DisenchantHelper", db.minimap)
            libDBIcon:Show("DisenchantHelper")
        end
        Print(L["MM_RESET"])
        return
    elseif msg == "clearblacklist" then
        wipe(GetModeBlacklist())
        Print(L["BLACKLIST_CLEARED"])
        if RefreshBlacklistUI then
            RefreshBlacklistUI()
        end
        RefreshList()
        return
    elseif msg == "compact" then
        SetCompactMode(not db.compactMode)
        return
    elseif msg == "options" or msg == "settings" then
        ToggleSettingsFrame()
        return
    elseif msg == "mail" then
        ns.MailUI.Toggle()
        return
    elseif msg == "check" then
        RunSelfCheck(false)
        return
    elseif msg == "copy" then
        RunSelfCheck(true)
        return
    elseif msg == "de" or string.sub(msg, 1, 3) == "de " then
        local arg = strtrim(string.sub(msg, 3))
        if not ns.Learn then
            return
        elseif arg == "reset" then
            Print(L[ns.Learn.Reset() and "LEARN_RESET_DONE" or "STORAGE_BLOCKED"])
            RefreshUI()
        elseif arg == "copy" then
            ShowCheckCopyWindow(table.concat(ns.Learn.BuildReport(true), "\n"))
        else
            for _, line in ipairs(ns.Learn.BuildReport(arg == "all")) do
                Print(line)
            end
        end
        return
    elseif msg == "stats" or string.sub(msg, 1, 6) == "stats " then
        local arg = strtrim(string.sub(msg, 6))
        if not ns.Stats then
            return
        elseif arg == "reset" then
            Print(L[ns.Stats.ResetSession() and "STATS_SESSION_RESET" or "STORAGE_BLOCKED"])
        elseif arg == "resetall" then
            Print(L[ns.Stats.ResetAll() and "STATS_ALL_RESET" or "STORAGE_BLOCKED"])
        else
            ToggleStatsFrame()
        end
        return
    elseif msg == "ev" or string.sub(msg, 1, 3) == "ev " then
        local arg = strtrim(string.sub(msg, 3))
        if arg == "on" then
            db.showExpected = true
        elseif arg == "off" then
            db.showExpected = false
        else
            db.showExpected = not (db.showExpected ~= false)
        end
        Print(db.showExpected ~= false and L["EV_TOGGLE_ON"] or L["EV_TOGGLE_OFF"])
        RefreshUI()
        return
    elseif msg == "help" or msg == "?" then
        PrintHelp()
        return
    elseif msg ~= "" then
        -- Unknown command: explain instead of silently toggling the window
        PrintHelp()
        return
    end

    ToggleMainFrame()
end

addon:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= ADDON_NAME then
            return
        end
        EnsureDB()
        ns.MailUI.Init(db, CreateStyledWindow)
        ns.ExternalTooltips.Init(db)
        if ns.Learn then
            ns.Learn.spellID = SPELL_ID_DISENCHANT
            pcall(ns.Learn.Init, db)
        end
        if ns.Stats then
            pcall(ns.Stats.Init, db)   -- after Learn.Init: backfills from learned data
        end
        if (ns.Learn and ns.Learn.storageBlocked) or (ns.Stats and ns.Stats.storageBlocked) then
            Print(L["STORAGE_BLOCKED"])
        end
        ApplyMode(db.activeMode)
        CreateMainFrame()
        CreateMinimapButton()
        CreateCompactFrame()
        CreateSettingsFrame()
    elseif event == "PLAYER_LOGIN" then
        RefreshList()
    elseif event == "BAG_UPDATE_DELAYED" then
        local anyShown = (mainFrame and mainFrame:IsShown()) or (compactFrame and compactFrame:IsShown())
        if anyShown then
            if InCombatLockdown() then
                -- Cannot rescan now (secure attributes are locked), but do NOT
                -- drop the update: loot during combat would otherwise leave the
                -- list AND the armed bag/slot target stale after combat ends.
                needsRefreshAfterCombat = true
            else
                RefreshList()
            end
        end
    elseif event == "CHAT_MSG_LOOT" then
        -- Loot shortly after the disenchant click = the cast succeeded:
        -- discard any pending blacklist validation. BUT only for OUR loot -
        -- in a group, CHAT_MSG_LOOT also fires for everyone else's pickups,
        -- and a party member looting within the window used to cancel the
        -- validation of a genuinely failed disenchant. Arg 12 of chat events
        -- is the source GUID; if it exists and is not us, ignore the message.
        if pendingDisenchantItem and GetTime() <= (pendingLootUntil or 0) then
            local sourceGUID = select(12, ...)
            local playerGUID = UnitGUID and UnitGUID("player")
            -- Keep validation pending when the loot owner cannot be inspected.
            if IsSecretValue(sourceGUID) or IsSecretValue(playerGUID) then
                return
            end
            local isOwnLoot = not (type(sourceGUID) == "string" and sourceGUID ~= ""
                and playerGUID and sourceGUID ~= playerGUID)
            if isOwnLoot then
                ClearPendingDisenchant()
            end
        end
    elseif event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" or event == "CHAT_MSG_SYSTEM" then
        if pendingDisenchantItem and GetTime() <= (pendingDisenchantUntil or 0) then
            local message = ExtractMessageFromEventArgs(...)
            local failureType = activeMode.classifyFailure(message)
            if failureType == "hard" then
                ValidatePendingItemForBlacklist(0.1)
            elseif failureType == "generic" then
                if TooltipSaysCantDisenchant(pendingDisenchantItem) then
                    AddPendingItemToBlacklist()
                else
                    ValidatePendingItemForBlacklist(0.25)
                end
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_SENT"
        or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit, guid, spellID = ...
        if event == "UNIT_SPELLCAST_SENT" then
            guid, spellID = select(3, ...)
        end
        if not IsSecretValue(unit) and unit == "player" and ns.Learn and not IsSecretValue(spellID) then
            if event == "UNIT_SPELLCAST_SENT" then
                pcall(ns.Learn.OnCastSent, spellID, guid)
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                pcall(ns.Learn.OnCastSucceeded, spellID, guid)
            else
                pcall(ns.Learn.OnCastFailed, spellID, guid)
            end
        end
    elseif event == "LOOT_OPENED" then
        if ns.Learn then
            pcall(ns.Learn.OnLootOpened)
        end
    elseif event == "UPDATE_BINDINGS" then
        -- The user may (re)bind the key in the client's Key Bindings window.
        RefreshHotkeyDisplay()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if db and db.compactMode and compactFrame and compactFrame:IsShown() and queueButton and queueButton:GetParent() ~= compactFrame then
            DockQueueButtonToCompact()
        end
        if needsRefreshAfterCombat then
            -- Bags changed during combat: full rescan (also re-arms the button).
            needsRefreshAfterCombat = false
            RefreshList()
        else
            UpdateQueueButton()
        end
        -- If we loaded during combat (/reload), the auto-hide driver could not
        -- be registered yet; do it now that we are out of combat.
        EnsureMainCombatHideDriver()
    end
end)

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("BAG_UPDATE_DELAYED")
addon:RegisterEvent("CHAT_MSG_LOOT")
addon:RegisterEvent("UI_ERROR_MESSAGE")
addon:RegisterEvent("UI_INFO_MESSAGE")
addon:RegisterEvent("CHAT_MSG_SYSTEM")
addon:RegisterEvent("PLAYER_REGEN_ENABLED")
addon:RegisterEvent("UPDATE_BINDINGS")
addon:RegisterEvent("LOOT_OPENED")
if addon.RegisterUnitEvent then
    addon:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
else
    addon:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end
-- Optional attribution events: retain the existing success-only path if absent.
pcall(addon.RegisterEvent, addon, "UNIT_SPELLCAST_SENT")
pcall(addon.RegisterEvent, addon, "UNIT_SPELLCAST_FAILED")
pcall(addon.RegisterEvent, addon, "UNIT_SPELLCAST_INTERRUPTED")
