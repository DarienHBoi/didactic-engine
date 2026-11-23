local _, S = ...
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
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
for _, ev in ipairs({ "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED" }) do
    pcall(f.RegisterEvent, f, ev)
end
-- Events that belong to one NectarKit module: unregistered while it is off, registered again when it is back on.
local MODULE_EVENTS = {
    maillog = { "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED" },
    customers = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" },
    trades = { "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_CLOSED", "UI_INFO_MESSAGE" },
}
local EVENT_MODULE = {}
for key, evs in pairs(MODULE_EVENTS) do
    for _, ev in ipairs(evs) do EVENT_MODULE[ev] = key end
    S.Mod.listen(key, function(on)
        for _, ev in ipairs(evs) do pcall(on and f.RegisterEvent or f.UnregisterEvent, f, ev) end
    end)
end
f:SetScript("OnEvent", function(_, event, arg1, arg2)
    if EVENT_MODULE[event] and not S.Mod.on(EVENT_MODULE[event]) then return end
    if event == "ADDON_LOADED" and arg1 == "Salesman" then
        SalesmanDB = SalesmanDB or {}
        SalesmanCharDB = SalesmanCharDB or {}
        S.DB.init(SalesmanDB, SalesmanCharDB)
        S.UI.initMinimapButton()
        pcall(S.UI.initMailHooks)
    elseif event == "PLAYER_LOGIN" then
        -- NectarKit module switches (queued for NectarKit when it is not loaded yet or not installed: then everything stays on).
        pcall(S.Mod.register)
    elseif event == "BAG_UPDATE_DELAYED" then
        if SalesmanWindow and SalesmanWindow:IsShown() then pcall(S.UI.refresh) end
    elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" or event == "MAIL_CLOSED" then
        pcall(S.UI.onMailEvent, event)
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
    if msg and msg:lower():find("^%s*mail") then
        -- Which mail functions this client has, and what the log holds.
        local function has(n) return type(_G[n]) == "function" and "yes" or "NO" end
        local l = S.DB.char and S.DB.char.mailLog or {}
        print("Salesman mail: GetInboxNumItems=" .. has("GetInboxNumItems") .. " GetInboxHeaderInfo=" .. has("GetInboxHeaderInfo")
            .. " GetInboxItem=" .. has("GetInboxItem") .. " GetInboxItemLink=" .. has("GetInboxItemLink")
            .. " GetInboxInvoiceInfo=" .. has("GetInboxInvoiceInfo") .. " logged=" .. #(l.entries or {})
            .. " waiting=" .. S.MailLog.waitingCount(l) .. " AH gold waiting=" .. S.Money.format(S.MailLog.uncollectedAH(l)))
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
