local _, P = ...

-- Copies Auctionator's figures into PricewatchDB: once after login, whenever the auction house closes, or by hand.
local function collect()
    if not P.db then return nil end
    local deps = {
        watch = function()
            return P.Watch.build(P.Watch.live())
        end,
        history = P.Adapters.history, posts = P.Adapters.posts, hour = P.Adapters.hour,
    }
    local today = P.Days.dayOf(time(), P.Days.epoch0())
    local res = P.Collector.run(P.db, deps, today)
    if P.Mod.on("market") then
        pcall(P.Market.prune, P.db, today)
        pcall(P.Rescan.resetWatch)
    end
    -- Names for the list, from the client's item cache when it has them.
    for id, it in pairs(P.db.items) do
        if not it.name then P.Store.setName(P.db, id, P.Adapters.itemInfo(id).name) end
    end
    return res
end
P.collect = collect

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
pcall(f.RegisterEvent, f, "AUCTION_HOUSE_CLOSED")
pcall(f.RegisterEvent, f, "AUCTION_HOUSE_SHOW")
pcall(f.RegisterEvent, f, "GET_ITEM_INFO_RECEIVED")
pcall(f.RegisterEvent, f, "MODIFIER_STATE_CHANGED")
pcall(f.RegisterEvent, f, "SKILL_LINES_CHANGED")
-- Sold tracker: every full search result of a watched item (ours, Auctionator's or the Blizzard UI's).
pcall(f.RegisterEvent, f, "ITEM_SEARCH_RESULTS_UPDATED")
pcall(f.RegisterEvent, f, "COMMODITY_SEARCH_RESULTS_UPDATED")
-- Disenchant logger: the player's casts and the loot window.
local DE_EVENTS = { UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true, LOOT_OPENED = true }
-- Loot log: gathering casts, the loot window, merchant prices (cook or sell raw).
local LOOT_EVENTS = { UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_CHANNEL_START = true, LOOT_OPENED = true,
    LOOT_SLOT_CLEARED = true, LOOT_CLOSED = true }
-- UNIT_ events for the player only where the client can (fewer wake-ups in groups); the handlers check the unit anyway.
local function reg(ev)
    if ev:find("^UNIT_") and f.RegisterUnitEvent and pcall(f.RegisterUnitEvent, f, ev, "player") then return end
    pcall(f.RegisterEvent, f, ev)
end
for ev in pairs(DE_EVENTS) do reg(ev) end
for ev in pairs(LOOT_EVENTS) do reg(ev) end
pcall(f.RegisterEvent, f, "MERCHANT_SHOW")
pcall(f.RegisterEvent, f, "MERCHANT_UPDATE")
P.eventFrame = f
f:SetScript("OnEvent", function(_, event, ...)
    local arg1, arg2 = ...
    if DE_EVENTS[event] or LOOT_EVENTS[event] then
        -- The disenchant logger first; the loot log skips that loot window itself (the Disenchant cast marks it).
        if DE_EVENTS[event] then pcall(P.DELog.onEvent, event, ...) end
        if LOOT_EVENTS[event] then pcall(P.Loot.onEvent, event, ...) end
        return
    end
    if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        if P.Mod.on("gather") then pcall(function() P.Cook.recordMerchant(P.db, P.Cook.readMerchant(), time()) end) end
        return
    end
    if event == "ADDON_LOADED" and arg1 == "Pricewatch" then
        PricewatchDB = P.Store.init(PricewatchDB)
        P.db = PricewatchDB
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Hook tooltips after the other addons (DisenchantBuddy hooks here too), so our line is the last one.
        if C_Timer and C_Timer.After then C_Timer.After(1, function() pcall(P.Tip.install) end) else pcall(P.Tip.install) end
        -- Best move under NectarKit's minimap tooltip (its button exists once NectarKit has logged in; tried again a little later).
        if not pcall(P.Best.hookMinimap) or not P.Best.hooked then
            if C_Timer and C_Timer.After then
                C_Timer.After(1, function() pcall(P.Best.hookMinimap) end)
                C_Timer.After(10, function() pcall(P.Best.hookMinimap) end)
            end
        end
    elseif event == "PLAYER_LOGIN" then
        -- NectarKit module switches (queued for NectarKit when it is not loaded yet or not installed: then everything stays on).
        pcall(P.Mod.register)
        pcall(P.DELog.reset)
        -- DisenchantHelper retired (audit step 7): take its learned rates once, while it is still loaded
        local okI, imp = pcall(P.DELog.importDH, P.db, DisenchantHelperDB)
        if okI and imp then
            print(("Pricewatch: imported DisenchantHelper's disenchant log once (%d brackets, %d samples). You can disable DisenchantHelper now."):format(imp.brackets, imp.samples))
        end
        pcall(P.DELog.installHooks)
        -- Give Auctionator and Salesman a few seconds to load their data first.
        if C_Timer and C_Timer.After then C_Timer.After(8, function() pcall(collect) end) else pcall(collect) end
    elseif event == "AUCTION_HOUSE_SHOW" then
        pcall(P.UI.Deals.onShow)
    elseif event == "SKILL_LINES_CHANGED" then
        pcall(P.Tip.resetCache)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        pcall(P.Tip.forgetItem, arg1) -- only that item's verdicts (audit step 2), not the whole cache
        pcall(P.Tip.onItemInfo, arg1, arg2)
        pcall(P.UI.Deals.onItemInfo, arg1, arg2)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        pcall(P.Rescan.onItemResults, arg1)
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        pcall(P.Rescan.onCommodityResults, arg1)
    elseif event == "MODIFIER_STATE_CHANGED" then
        pcall(P.Tip.onModifier, arg1)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        pcall(P.Best.reset)
        pcall(P.Rescan.stop)
        pcall(P.UI.Deals.onClose)
        pcall(P.Tip.resetCache)
        pcall(collect)
        if P.UI.state.frame and P.UI.state.frame:IsShown() then pcall(P.UI.refresh) end
    end
end)

-- Sold tracker off: stop listening to the search events at all; on: listen again (no reload).
P.Mod.listen("market", function(on)
    for _, ev in ipairs({ "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED" }) do
        pcall(on and f.RegisterEvent or f.UnregisterEvent, f, ev)
    end
end)

-- Other addons (Salesman's Best crafts) open the graph through this global.
function Pricewatch_Open(itemID) return pcall(P.UI.open, itemID) end

SLASH_PRICEWATCH1 = "/pricewatch"
SlashCmdList["PRICEWATCH"] = function(msg)
    if msg and msg:lower():find("snap") then
        local ok, res = pcall(collect)
        local n = 0
        for _ in pairs(P.db and P.db.items or {}) do n = n + 1 end
        print("Pricewatch: " .. (ok and res and ("copied " .. res.items .. " watched items, " .. res.failed .. " failed") or "copy failed")
            .. "; " .. n .. " items stored. Auctionator " .. (Auctionator and "found" or "NOT found")
            .. ", Salesman " .. (SalesmanAPI and "found" or "not found") .. ".")
        return
    end
    if msg and msg:lower():find("^%s*market") then
        local id = tonumber(msg:match("item:(%d+)") or msg:match("(%d+)"))
        for _, line in ipairs(P.Rescan.diagnose(id)) do print("Pricewatch: " .. line) end
        return
    end
    if msg and msg:lower():find("^%s*de%s*$") then
        for _, line in ipairs(P.DELog.report(P.db)) do print("Pricewatch: disenchants " .. line) end
        return
    end
    if msg and msg:lower():find("^%s*why") then
        local id = tonumber(msg:match("item:(%d+)") or msg:match("(%d+)"))
        local link = msg:match("(item:[%d:%-]+)") -- the item string: carries the level a scaled item really has
        for _, line in ipairs(P.Tip.diagnose(id, link)) do print("Pricewatch: " .. line) end
        return
    end
    local resolveArg = msg and msg:lower():match("^%s*resolve%s*(%a*)")
    if resolveArg then
        if resolveArg == "on" or resolveArg == "off" then
            P.Value.setResolveUse(resolveArg == "on")
            pcall(P.Tip.resetCache)
            print("Pricewatch: valuation now uses " .. (resolveArg == "on" and "the ZugDAQ-first resolver" or "the old price rule") .. ".")
        elseif resolveArg == "logging" then
            local onoff = msg:lower():match("logging%s+(%a+)")
            if onoff == "on" or onoff == "off" then P.Value.setResolveLogging(onoff == "on") end
            print("Pricewatch: resolver logging " .. (P.Value.resolveLogging() and "on" or "off") .. ".")
        elseif resolveArg == "clear" then
            P.db.resolveLog, P.db.resolveLogN = nil, 0
            print("Pricewatch: resolver log cleared.")
        else
            for _, line in ipairs(P.Value.resolveReport(resolveArg == "log" and 25 or 5)) do print("Pricewatch: " .. line) end
            if resolveArg ~= "log" then print("Pricewatch: /pricewatch resolve log | on | off | logging on|off | clear") end
        end
        return
    end
    if msg and msg:lower():find("^%s*tip%s+stats%s*$") then
        local st = P.Tip.cacheStats()
        print("Pricewatch: tooltip cache " .. st.hits .. " hits, " .. st.misses .. " misses" .. (st.rate and (" (" .. st.rate .. "% hits)") or ""))
        return
    end
    local marketArg = msg and msg:lower():match("^%s*tip%s+market%s*(.*)$")
    if marketArg then
        print((select(2, P.Tip.marketCommand(marketArg))))
        return
    end
    local mode = msg and msg:lower():match("^%s*tip%s+(%a+)")
    if mode or (msg and msg:lower():find("^%s*tip")) then
        if mode == "with" then mode = "shift" end
        if mode and P.Tip.setMode(mode) then
            print("Pricewatch: tooltip details: " .. mode)
        else
            print("Pricewatch: tooltip details are '" .. P.Tip.mode() .. "'. Use /pricewatch tip always, shift or never.")
        end
        return
    end
    if msg and msg:lower():find("^%s*today") then
        pcall(P.UI.openTab, "today")
        return
    end
    if msg and msg:lower():find("^%s*gather") then
        if not P.Mod.on("gather") then print("Pricewatch: the Gather tab is switched off in NectarKit (/nk options).") return end
        pcall(P.UI.openTab, "gather")
        return
    end
    if msg and msg:lower():find("^%s*items") then
        pcall(P.UI.openTab, "items")
        return
    end
    if msg and msg:lower():find("deals") then
        if not P.Mod.on("deals") then print("Pricewatch: the Deals panel is switched off in NectarKit (/nk options).") return end
        pcall(P.UI.Deals.toggle)
        return
    end
    P.UI.toggle()
end
