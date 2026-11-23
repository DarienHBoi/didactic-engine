local addonName, ns = ...

ns.TITLE = "ZugDAQ"
-- the version running: kept in step with the TOC's (a test checks). The TOC's is only read when the game starts,
-- this is read on every /reload, so it says which code is really loaded.
ns.VERSION = "2.6.2"

-- -1, 0 or 1, comparing "2.0.3" style versions part by part
function ns.CompareVersions(a, b)
    local pa, pb = {}, {}
    for n in tostring(a or ""):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b or ""):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

-- Is a newer addon waiting? The app says which version it ships (addon) and which is in the AddOns folder
-- (installed). Returns nil when this one is current, else:
--   "reload", version  the app has already put the new files in: /reload loads them
--   "update", version  the app ships a newer one: update it from the app, then /reload
function ns.AddonUpdate()
    local d = ns.AppData and ns.AppData()
    if not d or not d.addon or ns.CompareVersions(d.addon, ns.VERSION) <= 0 then return end
    if d.installed and ns.CompareVersions(d.installed, ns.VERSION) > 0 then return "reload", d.installed end
    return "update", d.addon
end

function ns.AddonUpdateText()
    local state, version = ns.AddonUpdate()
    if state == "reload" then
        return string.format("ZugDAQ %s is installed: type /reload to load it (you're running %s).", version, ns.VERSION)
    elseif state == "update" then
        return string.format("This addon is out of date (%s, the app has %s). Click \"Update addon\" at the bottom of the "
            .. "ZugDAQ app, then /reload.", ns.VERSION, version)
    end
end

local DEFAULTS = {
    valueMode = "best",     -- how loot and bags are valued: best (higher of AH and vendor), auction, vendor
    ahCut = 0.05,           -- auction house cut taken from sales, used when valuing items at AH price
    avgDays = 14,           -- days of price history behind "usual price"
    dealRatio = 0.75,       -- a listing at or below this share of the usual price is a deal
    dealMinValue = 5000,    -- ignore deals on items usually worth less than this (copper)
    dealMaxAge = 1,         -- only trust prices from a scan this many days old or newer
    autoScan = true,        -- scan the AH by itself on opening it, when the last full scan is old
    autoScanMinutes = 60,   -- ...older than this
    sellHighRatio = 1.15,   -- bag items priced this far above usual are worth selling now
    holdLowRatio = 0.85,    -- and this far below usual are worth holding
    logLimit = 4000,        -- transactions kept in the detailed log (daily totals are kept forever)
    liveShown = true,       -- show the small farming tracker while a session runs
    minimap = { hide = false }, -- LibDBIcon keeps the button's position in here too

    overviewDays = 30,      -- period shown on the overview: 7, 14, 30 or 90 days
    overviewMode = "daily", -- overview chart: daily bars or a running total
    incomeDays = 30,        -- period shown on the Income tab: 1, 7, 30, 90, or 0 for all time
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

-- WoW Forever's client hands addons some facts as "secret" values in combat (UnitIsAFK, UnitOnTaxi and the like): they
-- can be passed around but not tested, and "if secret then" is an error. This reads one safely: true only for a readable
-- true; a secret ("can't tell") counts as not true.
function ns.IsTrue(value)
    if issecretvalue then
        if issecretvalue(value) then return false end
        return value == true
    end
    local ok, result = pcall(function() return value == true end)
    return ok and result
end

function ns.Print(fmt, ...)
    local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    print("|cffffd700ZugDAQ|r: " .. text)
end

-- copper -> "12g 34s" with coloured letters; signed shows a leading +/-
function ns.Money(copper, signed)
    -- not a real amount (nil, NaN from 0/0, infinity from x/0): show nothing rather than break the tooltip it's in
    if type(copper) ~= "number" or copper ~= copper or copper == math.huge or copper == -math.huge then copper = 0 end
    copper = math.floor(copper + 0.5)
    local sign = ""
    if copper < 0 then sign = "-" copper = -copper elseif signed and copper > 0 then sign = "+" end
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local cp = copper % 100
    local G, S, C = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
    local text
    if gold >= 100 then
        text = string.format("%s%s", BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or gold, G)
    elseif gold > 0 then
        text = silver > 0 and string.format("%d%s %d%s", gold, G, silver, S) or string.format("%d%s", gold, G)
    elseif silver > 0 then
        text = cp > 0 and string.format("%d%s %d%s", silver, S, cp, C) or string.format("%d%s", silver, S)
    else
        text = string.format("%d%s", cp, C)
    end
    return sign .. text
end

-- signed money, green when positive and red when negative
function ns.MoneyColored(copper)
    if not copper or copper == 0 then return ns.Money(0) end
    local color = copper > 0 and "|cff40ff40" or "|cffff5050"
    return color .. (copper > 0 and "+" or "-") .. "|r" .. ns.Money(math.abs(copper))
end

function ns.Duration(seconds)
    seconds = math.floor(seconds or 0)
    local h = math.floor(seconds / 3600)
    local m = math.floor(seconds / 60) % 60
    if h > 0 then return string.format("%dh %02dm", h, m) end
    if m > 0 then return string.format("%dm %02ds", m, seconds % 60) end
    return string.format("%ds", seconds)
end

function ns.Percent(ratio)
    if not ratio then return "-" end
    return string.format("%d%%", math.floor(ratio * 100 + 0.5))
end

function ns.DayKey(t) return date("%Y-%m-%d", t or time()) end
function ns.Today() return ns.DayKey() end

-- day keys for the last n days, newest first
function ns.LastDays(n)
    local keys, now = {}, time()
    for i = 0, n - 1 do keys[#keys + 1] = ns.DayKey(now - i * 86400) end
    return keys
end

-- item shims: Forever runs a modern client, keep the classic globals as a fallback
function ns.GetItemInfo(item)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
    return GetItemInfo(item)
end

local requested = {}
function ns.RequestItem(itemID)
    if not itemID or requested[itemID] then return end
    requested[itemID] = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
end

function ns.ItemName(itemID)
    if not itemID then return end
    local name = ns.GetItemInfo(itemID)
    if not name then ns.RequestItem(itemID) end
    return name
end

function ns.ItemLink(itemID)
    if not itemID then return end
    local _, link = ns.GetItemInfo(itemID)
    if not link then ns.RequestItem(itemID) end
    return link
end

function ns.ItemIcon(itemID)
    if not itemID then return end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    return GetItemIcon and GetItemIcon(itemID)
end

-- itemID from a cached item name or a link, or nil
function ns.ItemIDFromName(name)
    if not name or name == "" then return end
    local id = tonumber(name:match("item:(%d+)"))
    if id then return id end
    local ok, instant
    if C_Item and C_Item.GetItemInfoInstant then
        ok, instant = pcall(C_Item.GetItemInfoInstant, name)
    elseif GetItemInfoInstant then
        ok, instant = pcall(GetItemInfoInstant, name)
    end
    if ok and type(instant) == "number" then return instant end
end

function ns.ItemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- coloured "[Name]" for an item, falling back to the stored name
function ns.ItemLabel(itemID, fallbackName)
    local link = ns.ItemLink(itemID)
    if link then return link end
    return "|cffffffff" .. (fallbackName or (itemID and ("item:" .. itemID)) or "?") .. "|r"
end

function ns.Container()
    return C_Container or {}
end

-- coalesces bursts of calls into one after `delay` seconds
local pending = {}
function ns.Debounce(key, delay, fn)
    if pending[key] then return end
    pending[key] = true
    C_Timer.After(delay, function()
        pending[key] = nil
        fn()
    end)
end

-- game events: several modules can listen to the same one; unknown events are skipped quietly
local handlers = {}
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    if ns.Trace then ns.Trace("event " .. event) end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- events the client forbids addons to register: asking for one is itself a blocked action
local FORBIDDEN_EVENTS = { COMBAT_LOG_EVENT_UNFILTERED = true, COMBAT_LOG_EVENT = true }

function ns.On(event, fn)
    if FORBIDDEN_EVENTS[event] then return end
    if not handlers[event] then
        handlers[event] = {}
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    table.insert(handlers[event], fn)
end

-- internal messages between modules ("MONEY", "SESSION", ...)
local listeners = {}
function ns.Listen(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end
function ns.Fire(message, ...)
    local list = listeners[message]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end

-- UI refresh, coalesced
function ns.RequestRefresh()
    ns.Debounce("refresh", 0.3, function() ns.Fire("REFRESH") end)
end

-- safe post-hook, only when the function exists: ns.Hook("GlobalName", fn) or ns.Hook(table, "name", fn)
function ns.Hook(tbl, name, fn)
    if type(tbl) == "string" then
        local globalName, hook = tbl, name
        if type(_G[globalName]) == "function" then
            hooksecurefunc(globalName, function(...)
                if ns.Trace then ns.Trace("hook " .. globalName) end
                return hook(...)
            end)
            return true
        end
        return false
    end
    if type(tbl) == "table" and type(tbl[name]) == "function" then
        hooksecurefunc(tbl, name, function(...)
            if ns.Trace then ns.Trace("hook " .. name) end
            return fn(...)
        end)
        return true
    end
    return false
end

local loadCallbacks = {}
function ns.OnLoad(fn) table.insert(loadCallbacks, fn) end
local loginCallbacks = {}
function ns.OnLogin(fn) table.insert(loginCallbacks, fn) end

ns.On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    -- moving in from Gold Ledger: its folder stays behind as a small stub that loads the old saved data (before this
    -- addon, as an optional dependency), and the first time ZugDAQ loads it takes that history over. The old file is
    -- left holding only a note; until the game saves on logout or /reload both files still hold the full history.
    if not (ZugDAQDB and ZugDAQDB.days) and type(GoldLedgerDB) == "table" and GoldLedgerDB.days then
        ZugDAQDB = GoldLedgerDB
        ZugDAQDB.movedFromGoldLedger = time()
        GoldLedgerDB = { movedToZugDAQ = time() }
        ns.movedIn = true
    end
    ZugDAQDB = ZugDAQDB or {}
    local db = ZugDAQDB
    db.settings = db.settings or {}
    applyDefaults(db.settings, DEFAULTS)
    db.chars = db.chars or {}        -- [char] = { money, seen, bags, bank, bagsBound, bankBound }
    db.wealth = db.wealth or {}      -- [day][char] = gold on hand at the end of that day
    db.days = db.days or {}          -- [day] = { inc = {cat = copper}, exp = {cat = copper}, online = seconds }
    db.log = db.log or {}            -- { t, c, k (category), a (amount), d (detail) }
    db.auctions = db.auctions or {}  -- [item name] = per-item auction stats
    db.sessions = db.sessions or {}  -- finished farming sessions
    db.watch = db.watch or {}        -- [itemID] = true
    db.warbank = db.warbank or {}
    db.version = 1
    ns.db = db
    ns.settings = db.settings
    for _, fn in ipairs(loadCallbacks) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Everything filed under one character key, moved to another (a duplicate folded into the real entry).
local function rekey(from, to)
    local db = ns.db
    local a, b = db.chars[from], db.chars[to]
    if a and b then
        -- the newer entry's state wins; recipes and skills from both
        local newer, older = a, b
        if (b.seen or 0) > (a.seen or 0) then newer, older = b, a end
        for k, v in pairs(older) do if newer[k] == nil then newer[k] = v end end
        for _, field in ipairs({ "recipes", "unlearned", "recipeObs", "profSkill" }) do
            if type(older[field]) == "table" and type(newer[field]) == "table" then
                for k, v in pairs(older[field]) do if newer[field][k] == nil then newer[field][k] = v end end
            end
        end
        db.chars[to] = newer
    elseif a then
        db.chars[to] = a
    end
    db.chars[from] = nil
    for _, perChar in pairs(db.wealth or {}) do
        if perChar[from] ~= nil then perChar[to] = perChar[from]; perChar[from] = nil end
    end
    for _, e in ipairs(db.log or {}) do if e.c == from then e.c = to end end
    for _, s in ipairs(db.sessions or {}) do if s.char == from then s.char = to end end
    for _, g in ipairs(db.gatherLog or {}) do if g.c == from then g.c = to end end
    if db.active and db.active.char == from then db.active.char = to end
    for _, field in ipairs({ "zones", "inventory" }) do
        local t = db[field]
        if type(t) == "table" and t[from] then
            if not t[to] then
                t[to] = t[from]
            elseif field == "inventory" then
                -- two logs of the same item: join them in time order
                for id, series in pairs(t[from]) do
                    local into = t[to][id]
                    if not into then t[to][id] = series
                    else
                        local pairsList = {}
                        for i = 1, #into - 1, 2 do pairsList[#pairsList + 1] = { into[i], into[i + 1] } end
                        for i = 1, #series - 1, 2 do pairsList[#pairsList + 1] = { series[i], series[i + 1] } end
                        table.sort(pairsList, function(x, y) return x[1] < y[1] end)
                        local joined = {}
                        for _, p in ipairs(pairsList) do joined[#joined + 1] = p[1]; joined[#joined + 1] = p[2] end
                        t[to][id] = joined
                    end
                end
            end
            t[from] = nil
        end
    end
end

-- The key this character is filed under. WoW Forever doesn't always give a realm name (after a /reload it can be
-- empty), so the character's GUID, which never changes, decides; then the one entry with the same name.
local function characterKey()
    local name = UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or ""
    if realm == "" and GetNormalizedRealmName then realm = GetNormalizedRealmName() or "" end
    local guid = UnitGUID and UnitGUID("player")
    local chars = ns.db.chars
    if guid then
        for key, c in pairs(chars) do if c.guid == guid then return key, guid end end
    end
    local prefix = name .. "-"
    local named = {}
    for key, c in pairs(chars) do
        if key:sub(1, #prefix) == prefix and key ~= prefix and (not guid or not c.guid) then named[#named + 1] = key end
    end
    -- one entry with this name from before characters were tagged: it's this one, whatever realm name it was filed under
    if #named == 1 then return named[1], guid end
    return prefix .. realm, guid
end

ns.On("PLAYER_LOGIN", function()
    local key, guid = characterKey()
    ns.charKey = key
    -- an entry made with no realm name ("Name-") is this character's too: fold it in
    local blank = (UnitName("player") or "?") .. "-"
    if key ~= blank and ns.db.chars[blank] then rekey(blank, key) end
    local c = ns.db.chars[ns.charKey] or {}
    ns.db.chars[ns.charKey] = c
    c.guid = guid or c.guid
    c.class = select(2, UnitClass("player"))
    if ns.movedIn then
        ns.Print("Gold Ledger is now part of ZugDAQ, and your history has moved over. Type /zug to open it " ..
            "(/ledger still works). You can delete the old GoldLedger and ProfessionGuide folders after your next logout.")
    end
    for _, fn in ipairs(loginCallbacks) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
    local outdated = ns.AddonUpdateText()
    if outdated then ns.Print("|cffff5050%s|r", outdated) end
end)

function ns.Day(key)
    key = key or ns.Today()
    local d = ns.db.days[key]
    if not d then
        d = { inc = {}, exp = {}, online = 0 }
        ns.db.days[key] = d
    end
    return d
end

-- minutes online per day, counted while the game runs
local lastTick
C_Timer.NewTicker(30, function()
    if not ns.db then return end
    local now = GetTime()
    if lastTick then
        local d = ns.Day()
        d.online = (d.online or 0) + math.min(now - lastTick, 120)
    end
    lastTick = now
end)

local function help()
    ns.Print("commands:")
    print("  /zug - show or hide the window")
    print("  /zug farm start [route name] - start a farming session (route defaults to the zone)")
    print("  /zug farm pause | resume | stop | cancel")
    print("  /zug watch <item link or name> - add an item to the market watchlist")
    print("  /zug unwatch <item link or name>")
    print("  /zug value best|auction|vendor - how looted items and bags are valued")
    print("  /zug deal <percent> - a listing at or under this % of the usual price counts as a deal (now "
        .. math.floor(ns.settings.dealRatio * 100) .. ")")
    print("  /zug autoscan on | off | <minutes> | now - scan the AH by itself when its prices are older than that (now "
        .. (ns.settings.autoScan and (ns.settings.autoScanMinutes .. " minutes") or "off") .. ")")
    print("  /zug live - show or hide the small farming tracker")
    print("  /zug minimap - show or hide the minimap button")
    print("  /zug blocked - what the game last blocked ZugDAQ from doing, and what led up to it")
    print("  /zug debug on | off | trail | clear - the debug log (on while blocks are tracked down)")
    print("  /zug bug <what happened> - report a bug to the server owner (the app sends it on, with any errors)")
    print("  /zug send [on | off] - reload now so the app gets the fresh AH prices you hold (on/off: the offer when closing the AH)")
end

function ZugDAQ_OnAddonCompartmentClick()
    if ns.ToggleFrame then ns.ToggleFrame() end
end

SLASH_ZUGDAQ1 = "/zug"
SLASH_ZUGDAQ2 = "/zugdaq"
SLASH_ZUGDAQ3 = "/ledger" -- Gold Ledger's old command still works
SlashCmdList.ZUGDAQ = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")
    if cmd == "" then
        if ns.ToggleFrame then ns.ToggleFrame() end
    elseif cmd == "farm" then
        local sub, arg = rest:match("^(%S*)%s*(.-)$")
        sub = strlower(sub or "")
        if sub == "start" then ns.StartSession(arg ~= "" and arg or nil)
        elseif sub == "pause" then ns.PauseSession()
        elseif sub == "resume" then ns.ResumeSession()
        elseif sub == "stop" then ns.StopSession()
        elseif sub == "cancel" then ns.CancelSession()
        else help() end
    elseif cmd == "watch" or cmd == "unwatch" then
        local id = ns.ItemIDFromName(rest)
        if not id then
            ns.Print("couldn't find that item. Shift-click it into the command, or use its exact name.")
            return
        end
        ns.SetWatched(id, cmd == "watch")
    elseif cmd == "value" and (rest == "best" or rest == "auction" or rest == "vendor") then
        ns.settings.valueMode = rest
        ns.Print("items are now valued by %s price.", rest == "best" and "the better of AH and vendor" or rest)
        ns.RequestRefresh()
    elseif cmd == "deal" and tonumber(rest) then
        ns.settings.dealRatio = math.max(0.05, math.min(1, tonumber(rest) / 100))
        ns.Print("deals: listings at or under %d%% of the usual price.", math.floor(ns.settings.dealRatio * 100))
        ns.RequestRefresh()
    elseif cmd == "autoscan" then
        local minutes = tonumber(rest)
        if rest == "off" then ns.settings.autoScan = false
        elseif rest == "on" then ns.settings.autoScan = true
        elseif minutes then ns.settings.autoScan, ns.settings.autoScanMinutes = true, math.max(15, math.floor(minutes))
        elseif rest == "now" then
            if ns.AutoScan then ns.AutoScan(true) end
            return
        end
        ns.Print("auto scan %s.", ns.settings.autoScan
            and string.format("on: when the AH is opened and the last full scan is over %d minutes old", ns.settings.autoScanMinutes)
            or "off")
    elseif cmd == "live" then
        ns.settings.liveShown = not ns.settings.liveShown
        if ns.UpdateLiveFrame then ns.UpdateLiveFrame() end
    elseif cmd == "minimap" then
        if ns.ToggleMinimapButton then ns.ToggleMinimapButton() end
    elseif cmd == "blocked" then
        if ns.BlockedCommand then ns.BlockedCommand() end
    elseif cmd == "send" then
        if ns.SendCommand then ns.SendCommand(rest) end
    elseif cmd == "bug" or cmd == "report" then
        if ns.BugCommand then ns.BugCommand(rest) end
    elseif cmd == "debug" then
        if ns.DebugCommand then ns.DebugCommand(rest) end
    else
        help()
    end
end
