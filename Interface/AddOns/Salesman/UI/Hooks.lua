local _, S = ...
S.Hooks = { buttons = {} }

-- Classic-style Enchanting may use either the TradeSkill API or the older Craft API.
-- Each adapter maps the client's functions to the shape S.Recipes.scan expects.
local function tradeSkillApi()
    if not GetNumTradeSkills then return nil end
    return {
        count = GetNumTradeSkills,
        info = function(i) local n, t = GetTradeSkillInfo(i); return n, t end,
        link = GetTradeSkillRecipeLink,
        numReagents = GetTradeSkillNumReagents,
        reagent = function(i, j)
            local name, icon, count = GetTradeSkillReagentInfo(i, j)
            return name, icon, count, GetTradeSkillReagentItemLink(i, j)
        end,
    }
end

local function craftApi()
    if not GetNumCrafts then return nil end
    return {
        count = GetNumCrafts,
        info = function(i) local n, _, t = GetCraftInfo(i); return n, t end,
        link = function(i) return (GetCraftRecipeLink or GetCraftItemLink)(i) end,
        numReagents = GetCraftNumReagents,
        reagent = function(i, j)
            local name, icon, count = GetCraftReagentInfo(i, j)
            return name, icon, count, GetCraftReagentItemLink(i, j)
        end,
    }
end

local function modernApi()
    if not C_TradeSkillUI then return nil end
    local basic = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1
    local helpers = { itemName = function(id)
        if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
        return (GetItemInfo and GetItemInfo(id)) or nil
    end }
    local api = S.Adapters.modern(C_TradeSkillUI, basic, helpers)
    if S.DB.global then S.DB.global.statsProbe = S.Adapters.probe end -- diagnostics: shows where the client keeps enchant text
    return api
end

local function baseProfession()
    local info = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    S.Hooks.lastBase = info
    return info
end

local function learnEnchantingName()
    local getInfo = (C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo
    local sp = getInfo and getInfo(7411)
    S.Recipes.enchantingName = type(sp) == "table" and sp.name or sp
end

function S.Hooks.apiAvailable()
    return modernApi() ~= nil or tradeSkillApi() ~= nil or craftApi() ~= nil
end

-- True when the open TradeSkill profession is Enchanting, or when that cannot be determined.
local function tradeSkillIsEnchanting()
    if not GetTradeSkillLine then return true end
    local line = GetTradeSkillLine()
    local getInfo = (C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo
    if not getInfo then return true end
    local info = getInfo(7411)
    local name = type(info) == "table" and info.name or info
    return name == nil or line == name
end

local function ensureButton(parent, id)
    if S.Hooks.buttons[id] or not parent then return end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(80, 22)
    -- Above the window's top-right edge so it cannot overlap the profession UI.
    b:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -10, 2)
    b:SetText("Salesman")
    b:SetScript("OnClick", S.UI.toggle)
    S.Hooks.buttons[id] = b
end

local function refreshFrom(api)
    if not api or not S.DB.char then return end
    S.Hooks.detected = api == S.Hooks.lastTS and "TradeSkill" or "Craft"
    local ok = pcall(S.Recipes.refresh, api)
    if ok and SalesmanWindow and SalesmanWindow:IsShown() then S.UI.refresh() end
end

-- The game only hands out the profession link while that profession is open; keep the Enchanting one.
local function captureSkillLink()
    learnEnchantingName()
    local getLink = (C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillListLink) or GetTradeSkillListLink
    if not getLink or not S.DB.char then return end
    local ok, link = pcall(getLink)
    if ok and type(link) == "string" then
        local name = link:match("|h%[([^%]]+)%]|h")
        if name then
            S.DB.char.skillLinks = S.DB.char.skillLinks or {}
            S.DB.char.skillLinks[name] = link
        end
        if S.Recipes.isSkillLink(link) then S.DB.char.skillLink = link end
    end
end

-- Another player's profession (chat link, guild view) must never overwrite the owner's recipes.
local function viewingSomeoneElse()
    local t = C_TradeSkillUI
    if not t then return false end
    for _, fn in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
        if t[fn] then
            local ok, v = pcall(t[fn])
            if ok and v then return true end
        end
    end
    return false
end

function S.Hooks.onTradeSkill()
    local parent = ProfessionsFrame or TradeSkillFrame
    if not parent then return end
    ensureButton(parent, "trade")
    if viewingSomeoneElse() then return end
    captureSkillLink()
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        -- Modern API (WoW Forever). Throttled: LIST_UPDATE can fire many times in a row.
        local now = GetTime()
        if S.Hooks.lastScan and now - S.Hooks.lastScan < 1 then
            -- Trailing scan: the last update of a burst must still be read once the burst is over.
            if not S.Hooks.pending and C_Timer and C_Timer.After then
                S.Hooks.pending = true
                C_Timer.After(1, function() S.Hooks.pending = false; S.Hooks.onTradeSkill() end)
            end
            return
        end
        learnEnchantingName()
        local base = baseProfession()
        do
            S.Hooks.lastTS = modernApi()
            S.Hooks.detected = "C_TradeSkillUI"
            if S.Hooks.lastTS and S.DB.char then
                -- Keep only Enchanting recipes: tag any recipe without its own profession info with the open one.
                local keep = function(r)
                    r.profession = r.profession or base
                    return S.Recipes.professionOf(r) ~= nil
                end
                local ok, list = pcall(S.Recipes.refresh, S.Hooks.lastTS, keep, true)
                -- Only throttle after a scan that found recipes; an early empty scan must not block the real one.
                if ok and list then S.Hooks.lastScan = now end
                if ok and SalesmanWindow and SalesmanWindow:IsShown() then S.UI.refresh() end
            end
        end
        return
    end
    if tradeSkillIsEnchanting() then
        S.Hooks.lastTS = tradeSkillApi()
        refreshFrom(S.Hooks.lastTS)
    end
end

function S.Hooks.onCraft()
    if not CraftFrame then return end
    ensureButton(CraftFrame, "craft")
    -- Only Enchanting uses the Craft window in the legacy API, but check the open line when the client tells us.
    if GetCraftDisplaySkillLine then
        learnEnchantingName()
        local line = GetCraftDisplaySkillLine()
        if line and S.Recipes.enchantingName and line ~= S.Recipes.enchantingName then return end
    end
    refreshFrom(craftApi())
end
