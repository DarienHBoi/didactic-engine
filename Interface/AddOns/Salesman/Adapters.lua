local _, S = ...
S.Adapters = {}

-- Adapter for the modern C_TradeSkillUI API (the one WoW Forever uses). Returns the table
-- S.Recipes.scan expects, or nil when the API is not there. basicType = Enum.CraftingReagentType.Basic.
function S.Adapters.modern(tsui, basicType, helpers)
    helpers = helpers or {}
    S.Adapters.probe = nil
    if type(tsui) ~= "table" or not tsui.GetAllRecipeIDs or not tsui.GetRecipeInfo or not tsui.GetRecipeSchematic then
        return nil
    end
    local rows = {}
    for _, id in ipairs(tsui.GetAllRecipeIDs() or {}) do
        local info = tsui.GetRecipeInfo(id)
        if info and info.learned and info.name then
            local slots = {}
            local schematic = tsui.GetRecipeSchematic(id, false)
            for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
                if slot.reagentType == basicType then slots[#slots + 1] = slot end
            end
            local link = tsui.GetRecipeLink and tsui.GetRecipeLink(id)
            if not link then
                link = "|cffffd000|Henchant:" .. id .. "|h[" .. info.name .. "]|h|r"
            end
            local category
            if tsui.GetCategoryInfo and info.categoryID then
                local ok, c = pcall(tsui.GetCategoryInfo, info.categoryID)
                category = ok and c and c.name or nil
            end
            local profession
            if tsui.GetProfessionInfoByRecipeID then
                local ok, p = pcall(tsui.GetProfessionInfoByRecipeID, id)
                profession = ok and p or nil
            end
            local resultLink
            if tsui.GetRecipeItemLink then
                local ok, l = pcall(tsui.GetRecipeItemLink, id)
                if ok and type(l) == "string" and l:find("|Hitem:", 1, true) then resultLink = l end
            end
            -- What the enchant gives, as the game words it (parsed into "+3 STR" by Stats.parse). Any lookup may be missing.
            local desc
            if tsui.GetRecipeDescription then
                local ok, d = pcall(tsui.GetRecipeDescription, id, {})
                if ok and type(d) == "string" then desc = d end
            end
            if not desc and schematic and type(schematic.description) == "string" then desc = schematic.description end
            if not desc and type(info.description) == "string" then desc = info.description end
            -- Diagnostics for the first recipes: where (if anywhere) the client keeps the enchant's text.
            if #rows < 3 then
                local function keys(t)
                    local k = {}
                    if type(t) == "table" then for key in pairs(t) do k[#k + 1] = tostring(key) end end
                    table.sort(k)
                    return table.concat(k, ",")
                end
                local viaFn
                if tsui.GetRecipeDescription then
                    local ok, d = pcall(tsui.GetRecipeDescription, id, {})
                    viaFn = ok and tostring(d) or ("error: " .. tostring(d))
                end
                S.Adapters.probe = S.Adapters.probe or {}
                S.Adapters.probe[#S.Adapters.probe + 1] = { name = info.name, hasFn = tsui.GetRecipeDescription ~= nil, viaFn = viaFn,
                    infoKeys = keys(info), schematicKeys = keys(schematic), desc = desc }
            end
            rows[#rows + 1] = { name = info.name, link = link, slots = slots, category = category, profession = profession, icon = info.icon, desc = desc, resultLink = resultLink }
        end
    end
    return {
        count = function() return #rows end,
        info = function(i) return rows[i].name, "optimal" end,
        link = function(i) return rows[i].link end,
        category = function(i) return rows[i].category end,
        profession = function(i) return rows[i].profession end,
        icon = function(i) return rows[i].icon end,
        desc = function(i) return rows[i].desc end,
        resultLink = function(i) return rows[i].resultLink end,
        numReagents = function(i) return #rows[i].slots end,
        reagent = function(i, j)
            local slot = rows[i].slots[j]
            local first = slot.reagents and slot.reagents[1]
            local link = first and first.itemID and ("|Hitem:" .. first.itemID .. "|h[item]|h") or nil
            local name = first and first.itemID and helpers.itemName and helpers.itemName(first.itemID) or nil
            return name, nil, slot.quantityRequired, link
        end,
    }
end
