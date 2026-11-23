local addonName, root = ...
root.PG = root.PG or {}
local ns = root.PG
ns.L = ns.L or {}
ns.Recipes = ns.Recipes or {}

ns.QUALITY_KEYS = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }

local DEFAULTS = {
    -- multiplier on a reagent's price by item quality: rarer reagents are scarcer than their price says
    qualityWeight = { [0] = 1, [1] = 1, [2] = 1.25, [3] = 2, [4] = 4, [5] = 8 },
    bagDiscount = true,    -- reagents already owned cost less (common ones nearly nothing)
    hideTrivial = true,    -- hide gray recipes
    onlyCraftable = false, -- only recipes the bags can make right now
    sortKey = "costPerPoint",
    farLookahead = false,  -- recipes-to-get: look 75 points ahead instead of 25
    autoShow = true,       -- open alongside the profession window
    docked = true,
    tab = "crafts",
}

local function applyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            applyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function ns.Print(fmt, ...)
    local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    print("|cff66bbffZugDAQ Professions|r: " .. text)
end

-- coalesces bursts of events into one call after `delay` seconds
local pendingCalls = {}
function ns.Debounce(key, delay, fn)
    if pendingCalls[key] then return end
    pendingCalls[key] = true
    C_Timer.After(delay, function()
        pendingCalls[key] = nil
        fn()
    end)
end

function ns.Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local cp = copper % 100
    local G, S, C = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
    if gold > 0 then
        if silver > 0 then return string.format("%d%s %d%s", gold, G, silver, S) end
        return string.format("%d%s", gold, G)
    elseif silver > 0 then
        if cp > 0 then return string.format("%d%s %d%s", silver, S, cp, C) end
        return string.format("%d%s", silver, S)
    end
    return string.format("%d%s", cp, C)
end

-- shims: Forever runs a modern client, but keep the classic globals as a fallback
function ns.GetItemInfo(itemID)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(itemID) end
    return GetItemInfo(itemID)
end

local requestedItems = {}
ns.requestedItems = requestedItems
function ns.RequestItem(itemID)
    if requestedItems[itemID] then return end
    requestedItems[itemID] = true
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
end

function ns.ItemName(itemID)
    local name = ns.GetItemInfo(itemID)
    if not name then ns.RequestItem(itemID) end
    return name or ("item:" .. itemID)
end

function ns.ItemQuality(itemID)
    local quality
    if C_Item and C_Item.GetItemQualityByID then quality = C_Item.GetItemQualityByID(itemID) end
    if quality == nil then
        quality = select(3, ns.GetItemInfo(itemID))
        if quality == nil then ns.RequestItem(itemID) end
    end
    return quality
end

function ns.QualityColor(quality)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c and c.hex then return c.hex end
    return "|cffffffff"
end

-- everything the account holds (every character's bags and bank, and the warbank): what the player owns
function ns.AccountCount(itemID)
    if root.AccountCount then return root.AccountCount(itemID) end
    return ns.ItemCount(itemID, true)
end

-- this character's bags (and reagent bag) only, or with its bank too
function ns.ItemCount(itemID, includeBank)
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(itemID, includeBank, false, includeBank) or 0
    end
    return GetItemCount(itemID, includeBank) or 0
end

-- vendor buy prices, recorded whenever a merchant window is open
local function captureMerchant()
    local prices = ZugDAQ_ProfDB.vendorPrices
    local count = GetMerchantNumItems and GetMerchantNumItems() or 0
    for index = 1, count do
        local itemID = GetMerchantItemID and GetMerchantItemID(index)
        local price, stack, extended
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(index)
            if info then price, stack, extended = info.price, info.stackCount, info.hasExtendedCost end
        elseif GetMerchantItemInfo then
            local _
            _, _, price, stack, _, _, _, extended = GetMerchantItemInfo(index)
        end
        if itemID and price and price > 0 and not extended then
            prices[itemID] = price / math.max(stack or 1, 1)
        end
    end
end

ns.callbacks = {}
function ns.OnRefresh(fn) table.insert(ns.callbacks, fn) end
function ns.RequestRefresh()
    ns.Debounce("refresh", 0.25, function()
        for _, fn in ipairs(ns.callbacks) do fn() end
    end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        -- moving in from Profession Guide (its folder stays behind as a stub that loads the old saved data first)
        if not (ZugDAQ_ProfDB and ZugDAQ_ProfDB.settings) and type(ProfessionGuideDB) == "table" and ProfessionGuideDB.settings then
            ZugDAQ_ProfDB = ProfessionGuideDB
            ProfessionGuideDB = { movedToZugDAQ = time() }
        end
        if not (ZugDAQ_ProfCharDB and ZugDAQ_ProfCharDB.professions) and type(ProfessionGuideCharDB) == "table"
            and ProfessionGuideCharDB.professions then
            ZugDAQ_ProfCharDB = ProfessionGuideCharDB
            ProfessionGuideCharDB = { movedToZugDAQ = time() }
        end
        ZugDAQ_ProfDB = ZugDAQ_ProfDB or {}
        ZugDAQ_ProfDB.settings = ZugDAQ_ProfDB.settings or {}
        applyDefaults(ZugDAQ_ProfDB.settings, DEFAULTS)
        -- 1.0.0 switched auto-open off when the panel was closed with X, and undocked it on any drag;
        -- put both back once
        if (ZugDAQ_ProfDB.settings.version or 1) < 2 then
            ZugDAQ_ProfDB.settings.autoShow = true
            ZugDAQ_ProfDB.settings.docked = true
            ZugDAQ_ProfDB.settings.version = 2
        end
        ZugDAQ_ProfDB.vendorPrices = ZugDAQ_ProfDB.vendorPrices or {}
        ZugDAQ_ProfDB.thresholds = ZugDAQ_ProfDB.thresholds or {}
        ZugDAQ_ProfCharDB = ZugDAQ_ProfCharDB or {}
        ZugDAQ_ProfCharDB.professions = ZugDAQ_ProfCharDB.professions or {}
        ns.settings = ZugDAQ_ProfDB.settings
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("MERCHANT_UPDATE")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        if ns.OnLoaded then ns.OnLoaded() end
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        ns.Debounce("merchant", 0.3, captureMerchant)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if arg1 and requestedItems[arg1] then ns.RequestRefresh() end
    elseif event == "BAG_UPDATE_DELAYED" then
        ns.RequestRefresh()
    end
end)

local function help()
    ns.Print("commands:")
    print("  /pg - open the guide: ZugDAQ's Crafting tab, Skill-ups (/zug opens the whole window)")
    print("  /pg quality <poor|common|uncommon|rare|epic> <weight> - how much extra a reagent of that quality counts (default 1 / 1 / 1.25 / 2 / 4)")
    print("  /pg quality - list the current weights")
    print("  /pg reset thresholds - forget learned skill-up color thresholds")
    print("  /pg reset prices - forget recorded vendor prices")
end

-- entry in the minimap's addon menu (TOC: AddonCompartmentFunc)
function ZugDAQ_Professions_OnAddonCompartmentClick()
    if ns.ToggleFrame then ns.ToggleFrame() end
end

SLASH_ZUGDAQPROF1 = "/pg"
SLASH_ZUGDAQPROF2 = "/zugprof"
SlashCmdList.ZUGDAQPROF = function(msg)
    local cmd, a, b = strsplit(" ", strlower(strtrim(msg or "")))
    if cmd == "" then
        if ns.ToggleFrame then ns.ToggleFrame() end
    elseif cmd == "quality" then
        local weights = ns.settings.qualityWeight
        if a and ns.QUALITY_KEYS[a] and tonumber(b) then
            weights[ns.QUALITY_KEYS[a]] = math.max(0, tonumber(b))
            ns.RequestRefresh()
        elseif a then
            return help()
        end
        local parts = {}
        for _, key in ipairs({ "poor", "common", "uncommon", "rare", "epic", "legendary" }) do
            local q = ns.QUALITY_KEYS[key]
            table.insert(parts, ns.QualityColor(q) .. key .. "|r " .. weights[q])
        end
        ns.Print("quality weights: %s", table.concat(parts, ", "))

    elseif cmd == "reset" and a == "thresholds" then
        wipe(ZugDAQ_ProfDB.thresholds)
        ns.Print("learned thresholds cleared")
        ns.RequestRefresh()
    elseif cmd == "reset" and a == "prices" then
        wipe(ZugDAQ_ProfDB.vendorPrices)
        ns.Print("recorded vendor prices cleared")
        ns.RequestRefresh()
    else
        help()
    end
end
