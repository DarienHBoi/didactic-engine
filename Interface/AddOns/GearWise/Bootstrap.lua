local addonName, ns = ...
ns.name, ns.version = addonName, "1.10.3-forever"
ns.UI, ns.API, ns.Rules, ns.Shopping = {}, {}, {}, {}
ns.slots = {
    {id=1, key="HeadSlot", label=ns.L("Kopf")}, {id=2, key="NeckSlot", label=ns.L("Hals")},
    {id=3, key="ShoulderSlot", label=ns.L("Schultern")}, {id=15, key="BackSlot", label=ns.L("Umhang")},
    {id=5, key="ChestSlot", label=ns.L("Brust")}, {id=9, key="WristSlot", label=ns.L("Armschienen")},
    {id=10, key="HandsSlot", label=ns.L("Hände")}, {id=6, key="WaistSlot", label=ns.L("Gürtel")},
    {id=7, key="LegsSlot", label=ns.L("Beine")}, {id=8, key="FeetSlot", label=ns.L("Füße")},
    {id=11, key="Finger0Slot", label=ns.L("Ring 1")}, {id=12, key="Finger1Slot", label=ns.L("Ring 2")},
    {id=16, key="MainHandSlot", label=ns.L("Waffenhand")}, {id=17, key="SecondaryHandSlot", label=ns.L("Nebenhand")},
    {id=18, key="RangedSlot", label=ns.L("Distanzwaffe")},
}
ns.slotByID = {}
for _, slot in ipairs(ns.slots) do ns.slotByID[slot.id] = slot end
ns.professions = {
    alchemy={id=171,name=ns.L("Alchemie"),spell=2259,english="Alchemy"},
    herbalism={id=182,name=ns.L("Kräuterkunde"),spell=2366,english="Herbalism"},
    mining={id=186,name=ns.L("Bergbau"),spell=2575,english="Mining"},
    skinning={id=393,name=ns.L("Kürschnerei"),spell=8613,english="Skinning"},
    cooking={id=185,name=ns.L("Kochkunst"),spell=2550,english="Cooking"},
    firstaid={id=129,name=ns.L("Erste Hilfe"),spell=3273,english="First Aid"},
    fishing={id=356,name=ns.L("Angeln"),spell=7620,english="Fishing"},
    enchanting={id=333, name=ns.L("Verzauberkunst"), spell=7411,english="Enchanting"},
    leatherworking={id=165, name=ns.L("Lederverarbeitung"), spell=2108,english="Leatherworking"},
    engineering={id=202, name=ns.L("Ingenieurskunst"), spell=4036,english="Engineering"},
    tailoring={id=197, name=ns.L("Schneiderei"), spell=3908,english="Tailoring"},
    blacksmithing={id=164, name=ns.L("Schmiedekunst"), spell=2018,english="Blacksmithing"},
}
function ns.IsForever(interface)
    interface = tonumber(interface)
    return interface ~= nil and interface >= 16000 and interface < 17000
end
function ns.Print(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff65d4ceGearWise:|r "..tostring(text)) end
end
-- pcall catches API errors, but a successful call may still return secret values.
-- Never inspect, compare, format or calculate with a value the client protects.
function ns.PublicValue(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end
function ns.IsPublicNumber(value)
    if issecretvalue and issecretvalue(value) then return false end
    return type(value)=="number" and value==value and math.abs(value)<1e12
end
function ns.Money(copper)
    if type(copper) ~= "number" then return ns.L("Preis unbekannt") end
    copper = math.max(0, math.floor(copper))
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    -- Native coin textures also work in embedded price text and wrapped resource rows.
    local gold, silver, bronze = math.floor(copper/10000), math.floor(copper/100)%100, copper%100
    local parts = {}
    if gold > 0 then parts[#parts+1] = gold.."|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t" end
    if silver > 0 then parts[#parts+1] = silver.."|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t" end
    if bronze > 0 or #parts == 0 then parts[#parts+1] = bronze.."|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t" end
    return table.concat(parts, "  ")
end
function ns.InitDB()
    if type(GearWiseDB) ~= "table" then GearWiseDB = {} end
    local db = GearWiseDB
    if db.schema ~= 2 then
        db.legacy = {settings=db.settings, cart=db.cart}
        db.settings, db.cart, db.characters = nil, nil, {}
        db.schema = 2
    end
    db.settings = type(db.settings) == "table" and db.settings or {}
    local defaults = {autoPriceImport=true,language="auto",chatLinkQuantity=true, onlyUpgradeIndicators=false, showRecipeHints=true, showCartContributions=true, showPriceAge=true, showIndicators=true, showMinimap=true, showUncertain=true, onlyUsable=false, sort="name"}
    for key,value in pairs(defaults) do if db.settings[key] == nil then db.settings[key] = value end end
    db.characters = type(db.characters) == "table" and db.characters or {}
    local key = UnitGUID("player") or ((UnitName("player") or "Player").."-"..(GetRealmName() or "Forever"))
    if type(db.characters[key]) ~= "table" then db.characters[key] = {} end
    ns.db, ns.char = db, db.characters[key]
    ns.Locale.Initialize()
    db.settings.autoAuctionator=nil
    ns.char.auctionatorListCreated=nil
    ns.char.cart = type(ns.char.cart) == "table" and ns.char.cart or {}
    ns.char.cartAdjustments = type(ns.char.cartAdjustments) == "table" and ns.char.cartAdjustments or {}
end
local events = CreateFrame("Frame")
ns.events = events
function ns.Refresh()
    if not ns.enabled or not ns.db then return end
    if ns.UI.RefreshIndicators then ns.UI.RefreshIndicators() end
    if ns.UI.Refresh then ns.UI.Refresh() end
    if ns.UI.RefreshPlanner then ns.UI.RefreshPlanner() end
    if ns.RecipeHints then ns.RecipeHints.Refresh() end
end
function ns.ScheduleRefresh()
    if not ns.enabled or ns.refreshPending then return end
    ns.refreshPending = true
    C_Timer.After(0.15, function()
        ns.refreshPending = nil
        ns.Refresh()
    end)
end
function ns.Start()
    if ns.started or not ns.enabled then return end
    ns.started = true
    ns.InitDB()
    ns.UI.Initialize()
    ns.UI.RegisterSettings()
    SLASH_GEARWISE1, SLASH_GEARWISE2 = "/gw", "/gearwise"
    SlashCmdList.GEARWISE = function(message)
        local command = string.lower((message or ""):match("^%s*(%S+)") or "")
        if command == "reset" then
            ns.db.settings.detached = nil
            ns.db.settings.cartPosition = nil
            ns.UI.PlacePanel()
            ns.Print(ns.L("Fenster wieder am Charakterfenster angedockt."))
        elseif command == "minimap" then
            ns.db.settings.showMinimap = not ns.db.settings.showMinimap
            ns.UI.RefreshMinimap()
        elseif command == "options" or command == "optionen" then
            ns.UI.OpenSettings()
        elseif command == "refresh" then
            ns.Refresh()
        elseif command == "status" then
            ns.Print("Forever "..ns.version.." | "..#ns.catalog..ns.L(" Einträge | Interface ")..tostring(ns.interface))
        elseif command == "help" then
            ns.Print(ns.L("/gw öffnen | /gw options | /gw reset | /gw minimap | /gw refresh | /gw status"))
        else
            ns.UI.Toggle()
        end
    end
    ns.UI.AttachSlots()
    ns.ScheduleRefresh()
end
events:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == addonName then
        local _, _, _, interface = GetBuildInfo()
        ns.interface, ns.enabled = interface, ns.IsForever(interface)
        if not ns.enabled then
            ns.Print(ns.L("Diese Ausgabe ist ausschließlich für WoW Forever (Interface 160xx)."))
            events:UnregisterAllEvents()
            return
        end
        if IsLoggedIn and IsLoggedIn() then ns.Start() end
    elseif event == "PLAYER_LOGIN" then
        ns.Start()
    elseif event == "ADDON_LOADED" then
        if ns.started then ns.UI.RegisterSettings();ns.UI.AttachSlots();ns.Shopping.OnEvent(event,arg);if ns.RecipeHints then ns.RecipeHints.Refresh() end end
    elseif ns.started then
        if event:match("^UNIT_") and arg and arg~="player" then return end
        ns.Shopping.OnEvent(event,arg)
        if event == "PLAYER_REGEN_ENABLED" then ns.UI.AttachSlots() end
        ns.ScheduleRefresh()
    end
end)
for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED",
    "GET_ITEM_INFO_RECEIVED", "SPELL_DATA_LOAD_RESULT", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "NEW_RECIPE_LEARNED", "PLAYER_LEVEL_UP", "UPDATE_FACTION",
    "PLAYER_REGEN_ENABLED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "PLAYER_LEAVING_WORLD", "ITEM_DATA_LOAD_RESULT", "PLAYER_TALENT_UPDATE",
    "UNIT_STATS", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_ATTACK_SPEED", "UNIT_DAMAGE", "UNIT_AURA", "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED",
}) do pcall(events.RegisterEvent, events, event) end


ns.Locale.Track(ns.slots)
for _,profession in pairs(ns.professions) do profession.german=profession.name end
ns.Locale.Track(ns.professions)
