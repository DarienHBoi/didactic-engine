local _, S = ...
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
-- Event names differ between client generations; an unknown one must never raise an error.
for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE",
                      "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
    pcall(f.RegisterEvent, f, ev)
end
-- The legacy Craft events may not exist on Forever; an unknown event must not error.
pcall(f.RegisterEvent, f, "CRAFT_SHOW")
pcall(f.RegisterEvent, f, "CRAFT_UPDATE")
for _, ev in ipairs({ "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_CLOSED", "UI_INFO_MESSAGE" }) do
    pcall(f.RegisterEvent, f, ev)
end
pcall(f.RegisterEvent, f, "BAG_UPDATE_DELAYED")
pcall(f.RegisterEvent, f, "CHAT_MSG_WHISPER")
pcall(f.RegisterEvent, f, "CHAT_MSG_WHISPER_INFORM")
f:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == "Salesman" then
        SalesmanDB = SalesmanDB or {}
        SalesmanCharDB = SalesmanCharDB or {}
        S.DB.init(SalesmanDB, SalesmanCharDB)
        S.UI.initMinimapButton()
    elseif event == "BAG_UPDATE_DELAYED" then
        if SalesmanWindow and SalesmanWindow:IsShown() then pcall(S.UI.refresh) end
    elseif event == "CHAT_MSG_WHISPER" then
        pcall(S.UI.onWhisper, arg1, arg2, false)
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        pcall(S.UI.onWhisper, arg1, arg2, true)
    elseif event == "TRADE_SHOW" or event == "TRADE_MONEY_CHANGED" or event == "TRADE_ACCEPT_UPDATE" or event == "TRADE_CLOSED" or event == "UI_INFO_MESSAGE" then
        pcall(S.UI.onTradeEvent, event, arg1, arg2)
    elseif event:find("^TRADE_SKILL") then
        S.Hooks.onTradeSkill()
    elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        S.Hooks.onCraft()
    end
end)

SLASH_SALESMAN1 = "/salesman"
SlashCmdList["SALESMAN"] = function(msg)
    if msg and msg:lower():find("minimap") then
        S.UI.setMinimapShown(S.DB.global.minimapHidden)
        print("Salesman minimap button " .. (S.DB.global.minimapHidden and "hidden" or "shown"))
        return
    end
    if msg and msg:lower():find("art") then
        -- Saves the atlas names the Blizzard Encounter Journal uses into SalesmanDB.artDump (read it from the SavedVariables file).
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then pcall(load, "Blizzard_EncounterJournal") end
        local seen, out = {}, {}
        local function walk(fr, depth)
            if depth > 5 or #out >= 150 then return end
            for _, reg in ipairs({ fr:GetRegions() }) do
                local a = reg.GetAtlas and reg:GetAtlas()
                if a and not seen[a] then seen[a] = true; out[#out + 1] = a end
            end
            for _, ch in ipairs({ fr:GetChildren() }) do walk(ch, depth + 1) end
        end
        if EncounterJournal then pcall(walk, EncounterJournal, 0) end
        SalesmanDB.artDump = out
        print("Salesman art: saved " .. #out .. " atlas names (EncounterJournal " .. (EncounterJournal and "found" or "missing") .. "). /reload to write them to disk.")
        return
    end
    if msg and msg:lower():find("debug") then
        local function has(n) return _G[n] ~= nil and "yes" or "no" end
        print("Salesman debug: GetNumTradeSkills=" .. has("GetNumTradeSkills") .. " GetNumCrafts=" .. has("GetNumCrafts")
            .. " C_TradeSkillUI=" .. has("C_TradeSkillUI") .. " TradeSkillFrame=" .. has("TradeSkillFrame")
            .. " CraftFrame=" .. has("CraftFrame") .. " ProfessionsFrame=" .. has("ProfessionsFrame") .. " Auctionator=" .. (S.Prices.available() and "yes" or "no")
            .. " detected=" .. tostring(S.Hooks.detected) .. " skin=" .. tostring(S.UI.skin or "not built yet")
            .. " lastProfession=" .. tostring(S.Hooks.lastBase and (tostring(S.Hooks.lastBase.professionID) .. "/" .. tostring(S.Hooks.lastBase.professionName)) or "none") .. " cachedRecipes=" .. tostring(S.DB.char and #S.DB.char.recipes or "n/a"))
        return
    end
    S.UI.toggle()
end
