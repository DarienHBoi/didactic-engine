local _, ns = ...

-- Debug: finding out why the game blocks an action and blames ZugDAQ ("ZugDAQ has been blocked from an action only
-- available to the Blizzard UI").
--
--   * a trail of the last things ZugDAQ did (events it handled, hooks that fired, clicks, tooltips, AH searches),
--     so a block can be matched to what led up to it;
--   * every block the game reports (ours and other addons'), with the function it blocked and that trail, kept in
--     ZugDAQDB.debug.blocked for the app's Addon debug window and /zug blocked;
--   * WoW's own taint log (the taintLog CVar), which writes Logs\taint.log with exactly which addon code touched
--     Blizzard's, and where. The app reads that file too.
--
-- On by default while the block is being tracked down; /zug debug off turns it all off (and the taint log back off).

local TRAIL_SIZE = 60
local trail = {}

-- a breadcrumb: the same thing repeated within a couple of seconds counts up instead of filling the trail
function ns.Trace(what)
    local now = GetTime()
    local last = trail[#trail]
    if last and last.w == what and now - last.g < 2 then
        last.n, last.g = last.n + 1, now
        return
    end
    trail[#trail + 1] = { w = what, t = time(), g = now, n = 1, c = InCombatLockdown and InCombatLockdown() or false }
    if #trail > TRAIL_SIZE then table.remove(trail, 1) end
end

local function trailLines(count)
    local out = {}
    for i = math.max(1, #trail - count + 1), #trail do
        local e = trail[i]
        out[#out + 1] = string.format("%s%s %s%s", date("%H:%M:%S", e.t), e.c and " [combat]" or "", e.w, e.n > 1 and (" x" .. e.n) or "")
    end
    return out
end

local function debugOn() return ns.settings and ns.settings.debug ~= false end

local function setTaintLog(level)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if set then pcall(set, "taintLog", tostring(level)) end
end

local function onBlocked(event, addon, func)
    if not ns.db then return end
    local dbg = ns.db.debug or {}
    ns.db.debug = dbg
    dbg.blocked = dbg.blocked or {}
    local entry = {
        t = time(), event = event, addon = addon, func = func,
        combat = InCombatLockdown and InCombatLockdown() or false,
        trail = trailLines(25),
        stack = debugstack and debugstack(2, 20, 0) or nil,
    }
    table.insert(dbg.blocked, entry)
    while #dbg.blocked > 30 do table.remove(dbg.blocked, 1) end
    if addon == "ZugDAQ" and debugOn() then
        ns.Print("|cffff5050debug:|r the game blocked |cffffffff%s|r%s. Logged with what ZugDAQ was doing just before; "
            .. "/reload, then open Addon debug in the ZugDAQ app (or /zug blocked).", tostring(func), entry.combat and " in combat" or "")
    end
end
-- every addon's blocks, not just ours: the game sometimes blames the wrong one
ns.On("ADDON_ACTION_BLOCKED", function(...) onBlocked("ADDON_ACTION_BLOCKED", ...) end)
ns.On("ADDON_ACTION_FORBIDDEN", function(...) onBlocked("ADDON_ACTION_FORBIDDEN", ...) end)
ns.On("MACRO_ACTION_BLOCKED", function(...) onBlocked("MACRO_ACTION_BLOCKED", nil, ...) end)

ns.OnLogin(function()
    if not debugOn() then return end
    setTaintLog(2)
    ns.db.debug = ns.db.debug or {}
    ns.db.debug.session = { started = time(), client = select(1, GetBuildInfo()), build = select(2, GetBuildInfo()) }
    ns.Trace("login")
end)

-- the trail as it stood at logout, for blocks the game didn't report as an event
ns.On("PLAYER_LOGOUT", function()
    if ns.db and ns.db.debug and debugOn() then ns.db.debug.lastTrail = trailLines(TRAIL_SIZE) end
end)

function ns.DebugCommand(rest)
    rest = strtrim(rest or "")
    if rest == "off" then
        ns.settings.debug = false
        setTaintLog(0)
        ns.Print("debug off (taint log off too).")
    elseif rest == "on" then
        ns.settings.debug = true
        setTaintLog(2)
        ns.Print("debug on: blocks are announced and logged, and the game's taint log (Logs\\taint.log) is on.")
    elseif rest == "clear" then
        if ns.db.debug then ns.db.debug.blocked = {} end
        ns.Print("debug log cleared.")
    elseif rest == "trail" then
        ns.Print("the last things ZugDAQ did:")
        for _, line in ipairs(trailLines(20)) do print("   " .. line) end
    else
        ns.Print("debug is %s. /zug debug on | off | trail | clear", debugOn() and "on" or "off")
    end
end

-- ---------------------------------------------------------------- Lua errors and bug reports
--
-- Every Lua error that comes from ZugDAQ's own files is kept (once per message, counted) in ZugDAQDB.debug.errors,
-- with what the addon was doing just before. /zug bug <what happened> saves a note in ZugDAQDB.debug.reports. The app
-- reads both when the game saves (/reload or logout) and sends them to the server owner.

local ERRORS_KEPT, REPORTS_KEPT = 25, 15
local announced = {}
local early = {} -- errors before the saved data is loaded

local function version() return ns.VERSION end

local function isOurs(msg, stack)
    return (tostring(msg) .. "\n" .. (stack or "")):find("AddOns[/\\]ZugDAQ[/\\]") ~= nil
end

local function storeError(e)
    local dbg = ns.db.debug or {}
    ns.db.debug = dbg
    dbg.errors = dbg.errors or {}
    for _, old in ipairs(dbg.errors) do
        if old.msg == e.msg and old.v == e.v then
            old.n, old.last = (old.n or 1) + e.n, e.last
            return
        end
    end
    table.insert(dbg.errors, e)
    while #dbg.errors > ERRORS_KEPT do table.remove(dbg.errors, 1) end
end

local function recordError(msg, stack)
    msg = tostring(msg or "?")
    if not isOurs(msg, stack) then return end
    local now = time()
    local e = {
        msg = msg:sub(1, 500), stack = stack and stack:sub(1, 2500) or nil, first = now, last = now, n = 1, v = version(),
        combat = InCombatLockdown and InCombatLockdown() or false, trail = trailLines(15),
    }
    if ns.db then storeError(e) elseif #early < 10 then early[#early + 1] = e end
    if not announced[msg] and ns.Print then
        announced[msg] = true
        ns.Print("|cffff5050hit an error|r (saved for the bug report: the app sends it to the server owner after a /reload). "
            .. "Add what you were doing with /zug bug <what happened>.")
    end
end

-- chain onto whatever error handler is there (the game's popup, or another addon's), never replacing what it does
local viaBugGrabber = false
do
    local previous = geterrorhandler and geterrorhandler()
    if previous and seterrorhandler then
        seterrorhandler(function(msg, ...)
            if not viaBugGrabber then pcall(recordError, msg, debugstack and debugstack(3, 25, 0)) end
            return previous(msg, ...)
        end)
    end
end

ns.OnLoad(function()
    -- errors from an older version of the addon: fixed since (or already reported by the app), so they go
    local dbg = ns.db.debug
    if dbg and dbg.errors then
        for i = #dbg.errors, 1, -1 do
            if dbg.errors[i].v ~= ns.VERSION then table.remove(dbg.errors, i) end
        end
    end
    for _, e in ipairs(early) do storeError(e) end
    early = {}
end)

-- BugGrabber (BugSack) keeps the error handler to itself: hear about errors from it instead
ns.OnLogin(function()
    local bg = _G.BugGrabber
    if type(bg) == "table" and type(bg.RegisterCallback) == "function" then
        local ok = pcall(bg.RegisterCallback, ns, "BugGrabber_BugGrabbed", function(_, err)
            if type(err) == "table" then pcall(recordError, err.message, err.stack) end
        end)
        viaBugGrabber = ok
    end
end)

-- /zug bug <what happened>: a note for the server owner, with what the addon did just before
function ns.BugCommand(text)
    text = strtrim(text or "")
    if text == "" then
        local errors = ns.db and ns.db.debug and ns.db.debug.errors or {}
        ns.Print("/zug bug <what happened> saves a bug report; the ZugDAQ app sends it to the server owner after a /reload "
            .. "(or the app's Report a bug button). %d error%s saved so far%s.", #errors, #errors == 1 and "" or "s",
            #errors > 0 and (": the newest is |cffffffff" .. errors[#errors].msg:sub(1, 120) .. "|r") or "")
        return
    end
    local dbg = ns.db.debug or {}
    ns.db.debug = dbg
    dbg.reports = dbg.reports or {}
    local name, realm = UnitFullName and UnitFullName("player")
    table.insert(dbg.reports, {
        t = time(), text = text:sub(1, 1000), v = version(),
        char = name and (name .. "-" .. (realm or GetRealmName() or "")) or UnitName("player"),
        zone = GetRealZoneText and GetRealZoneText() or nil,
        trail = trailLines(25),
    })
    while #dbg.reports > REPORTS_KEPT do table.remove(dbg.reports, 1) end
    ns.Print("bug report saved, thanks. |cffffffff/reload|r to hand it to the ZugDAQ app now (it sends it on), or it goes at logout.")
end

function ns.BlockedCommand()
    local list = ns.db and ns.db.debug and ns.db.debug.blocked or {}
    if #list == 0 then ns.Print("nothing has been blocked since debug started.") return end
    for i = math.max(1, #list - 4), #list do
        local b = list[i]
        ns.Print("%s: %s blocked |cffffffff%s|r (%s)%s", date("%d %b %H:%M:%S", b.t), b.addon or "?", tostring(b.func), b.event,
            b.combat and " in combat" or "")
    end
    local last = list[#list]
    if last.trail and #last.trail > 0 then
        print("   just before the last one:")
        for i = math.max(1, #last.trail - 7), #last.trail do print("     " .. last.trail[i]) end
    end
end
