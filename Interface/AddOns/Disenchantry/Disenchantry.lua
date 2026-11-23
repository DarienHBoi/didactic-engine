-- Entry point: initialize services, dispatch client events and expose commands.
local addonName, ns = ...
local App = ns.App
local events, commands = {}, {}
ns.Events = events

local function visible()
    return App.mainFrame and App.mainFrame:IsShown() or App.compactFrame and App.compactFrame:IsShown()
end
local function refreshVisible()
    if not visible() then return end
    if InCombatLockdown() then App.needsRefreshAfterCombat = true else App.RefreshWorkspace() end
end

function events.ADDON_LOADED(name)
    if name ~= addonName then return end
    App.OpenPreferences()
    App.ActivateProfession(App.db.activeMode)
    ns.Statistics.Initialize(App.db, App.CreateStyledWindow, App.CreateStyledButton)
    App.CreateMainFrame()
    App.CreateMinimapButton()
    App.CreateCompactFrame()
    ns.Hotkeys.Initialize(App.db, App.queueButton, function()
        return App.activeMode.key == "disenchant" and App.queueButton:IsVisible()
    end)
    ns.DisenchantResults.InstallTooltipHooks()
    App.CreateSettingsFrame()
end
function events.PLAYER_LOGIN() App.RefreshWorkspace() end
local lastSalvager
function events.UNIT_AURA(unit)
    if unit~="player" or not App.db then return end
    local active=ns.ForecastPolicy.SalvagerActive()
    if lastSalvager~=active then
        lastSalvager=active
        App.ForecastPreferencesChanged()
    end
end
function events.BAG_UPDATE_DELAYED() refreshVisible() end
function events.GET_ITEM_INFO_RECEIVED(id, success)
    if not ns.DisenchantResults.ItemLoaded(id) or not success then return end
    if InCombatLockdown() then App.needsRefreshAfterCombat = true
    elseif visible() then App.RefreshUI() end
end
function events.CHAT_MSG_LOOT(...)
    if not App.pendingDisenchantItem or GetTime() > App.pendingLootUntil then return end
    local source = select(12, ...)
    local player = UnitGUID and UnitGUID("player")
    if issecretvalue and (issecretvalue(source) or issecretvalue(player)) then return end
    if ns.Client.IsPublicString(source) and player then
        local ok, foreign = pcall(function() return source ~= player end)
        if ok and foreign then return end
    end
    App.ClearPendingDisenchant()
end
local function processingMessage(...)
    if not App.pendingDisenchantItem or GetTime() > App.pendingDisenchantUntil then return end
    local failure = App.activeMode.classifyFailure(App.ExtractMessageFromEventArgs(...))
    if failure == "hard" then App.ValidatePendingItemForBlacklist(0.1, true)
    elseif failure == "generic" then
        App.ValidatePendingItemForBlacklist(0.25)
    end
end
events.UI_ERROR_MESSAGE, events.UI_INFO_MESSAGE, events.CHAT_MSG_SYSTEM = processingMessage, processingMessage, processingMessage
function events.PLAYER_REGEN_ENABLED()
    App.InstallCombatVisibility()
    ns.Hotkeys.Update()
    if App.db and App.db.compactMode and App.compactFrame and App.compactFrame:IsShown()
        and App.queueButton:GetParent() ~= App.compactFrame then App.DockQueueButtonToCompact() end
    if App.needsRefreshAfterCombat then
        App.needsRefreshAfterCombat = false
        App.RefreshWorkspace()
    else App.RefreshWorkspace() end
end
function events.PLAYER_REGEN_DISABLED()
    App.ClearPendingDisenchant()
    App.needsRefreshAfterCombat = true
    App.HideMainFrameForCombat()
end
function events.AUCTION_HOUSE_CLOSED()
    ns.Prices.ClearCache()
    ns.Statistics.Refresh()
    refreshVisible()
end

local help = {
    {"", "HELP_TOGGLE"}, {"blacklist", "OPEN_BLACKLIST"}, {"de | mill | prospect", "MODE_SWITCH_HINT"},
    {"compact", "HELP_COMPACT"}, {"settings", "HELP_OPTIONS"}, {"show | hide | reset", "HELP_MINIMAP"},
    {"refresh", "HELP_REFRESH"}, {"clearblacklist", "HELP_CLEARBLACKLIST"}, {"check", "HELP_CHECK"}, {"copy", "HELP_COPY"},
}
function App.PrintHelp()
    App.Print(App.L.HELP_HEADER)
    for _, entry in ipairs(help) do App.Print("  /ed " .. entry[1] .. " - " .. App.L[entry[2]]) end
end
commands[""] = App.ToggleMainFrame
commands.blacklist = App.ToggleBlacklistFrame
commands.compact = function() App.SetCompactMode(not App.db.compactMode) end
commands.settings = App.ToggleSettingsFrame
commands.options = commands.settings
commands.help = App.PrintHelp
commands["?"] = App.PrintHelp
commands.refresh = function() App.RefreshWorkspace(); App.Print(App.L.LIST_REFRESHED) end
commands.check = function() App.InspectWorkspace(false) end
commands.copy = function() App.InspectWorkspace(true) end
commands.clearblacklist = function()
    wipe(App.ExclusionBook())
    App.Print(App.L.BLACKLIST_CLEARED)
    App.RefreshBlacklistUI()
    App.RefreshWorkspace()
end
local function minimap(show, reset)
    App.db.minimap.hide = not show
    if reset then App.db.minimap.minimapPos = 220 end
    if App.libDBIcon then
        if reset then App.libDBIcon:Refresh("Disenchantry", App.db.minimap) end
        if show then App.libDBIcon:Show("Disenchantry") else App.libDBIcon:Hide("Disenchantry") end
    end
    App.Print(App.L[reset and "MM_RESET" or show and "MM_SHOWN" or "MM_HIDDEN"])
end
commands.show = function() minimap(true) end
commands.hide = function() minimap(false) end
commands.reset = function() minimap(true, true) end
commands.resetbutton = commands.reset
local function chooseMode(key)
    local mode = ns.Modes.byKey[key]
    if not App.SupportsProfession(mode) or not mode.isKnown() then App.Print(App.L.MODE_NOT_LEARNED_HINT); return end
    local _, changed = App.ChooseProfession(key)
    if not changed and not InCombatLockdown() then App.Print(App.L.MODE_NOT_LEARNED_HINT) end
end
commands.de = function() chooseMode("disenchant") end
commands.mill = function() chooseMode("milling") end
commands.prospect = function() chooseMode("prospecting") end
SLASH_DISENCHANTRY1, SLASH_DISENCHANTRY2 = "/ed", "/disenchantry"
SlashCmdList.DISENCHANTRY = function(message)
    if App.db then (commands[string.lower(strtrim(message or ""))] or App.PrintHelp)() end
end

App.addon:SetScript("OnEvent", function(_, event, ...)
    ns.Statistics.OnEvent(event, ...)
    local handler = events[event]
    if handler then handler(...) end
end)
for event in pairs(events) do App.addon:RegisterEvent(event) end
for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "AUCTION_HOUSE_CLOSED"}) do App.addon:RegisterEvent(event) end
