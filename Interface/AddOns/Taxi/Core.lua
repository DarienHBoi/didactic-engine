-- Taxi core: filter building, /who search, sent marks, paced sender. No UI here.
local ADDON, ns = ...

ns.CLASSES = { "Any", "Warlock", "Priest", "Mage", "Rogue", "Hunter", "Warrior", "Paladin", "Shaman", "Druid" }
ns.TABS = { "Going", "Stay", "LFG" }
ns.SEND_GAP = 1.5      -- seconds between whispers
ns.MARK_TTL = 300      -- seconds a sent mark blocks a repeat whisper
ns.WHO_TIMEOUT = 6     -- seconds to wait for a who reply
ns.WHO_CAP = 50        -- the client returns at most this many
ns.DEFAULT_MSG = {
    Going = "Hi! Could you summon me please? Thank you!",
    Stay = "Hi! Could you help summon a friend to me please? Thank you!",
    LFG = "Hi! Want to group up? Thanks!",
}

-- Vanilla dungeons sorted by minimum level; ranges are the usual classic ones.
ns.DUNGEONS = {
    { "Ragefire Chasm", 13, 18 }, { "The Deadmines", 10, 20 }, { "Wailing Caverns", 15, 25 },
    { "Shadowfang Keep", 18, 25 }, { "Blackfathom Deeps", 20, 30 }, { "The Stockade", 22, 30 },
    { "Gnomeregan", 24, 33 }, { "Razorfen Kraul", 25, 35 }, { "Scarlet Monastery", 28, 38 },
    { "Razorfen Downs", 35, 45 }, { "Uldaman", 35, 47 }, { "Zul'Farrak", 42, 50 },
    { "Maraudon", 45, 55 }, { "Sunken Temple", 50, 60 }, { "Blackrock Depths", 52, 60 },
    { "Lower Blackrock Spire", 55, 60 }, { "Dire Maul", 58, 60 }, { "Scholomance", 58, 60 },
    { "Stratholme", 58, 60 }, { "Upper Blackrock Spire", 58, 60 },
}
table.sort(ns.DUNGEONS, function(a, b)
    if a[2] ~= b[2] then return a[2] < b[2] end
    if a[3] ~= b[3] then return a[3] < b[3] end
    return a[1] < b[1]
end)

function ns.DungeonMessage(name) return "Hi! Want to run " .. name .. "? Thanks!" end

-- fills the level range and message for a dungeon on the given tab
function ns.ApplyDungeon(tab, d)
    local db = ns.GetDB()
    db.lmin[tab], db.lmax[tab] = tostring(d[2]), tostring(d[3])
    db.msg[tab] = ns.DungeonMessage(d[1])
end

ns.clock = function() return time() end
ns.ticked = { Going = {}, Stay = {}, LFG = {} }

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
ns.trim = trim

function ns.GetDB()
    TaxiDB = TaxiDB or {}
    local db = TaxiDB
    db.tab = db.tab or "Going"
    db.msg, db.class, db.place, db.sent = db.msg or {}, db.class or {}, db.place or {}, db.sent or {}
    db.results = db.results or {} -- last search list per tab, kept across reopen/relog
    for _, t in ipairs(ns.TABS) do
        if db.msg[t] == nil then db.msg[t] = ns.DEFAULT_MSG[t] end
        db.class[t] = db.class[t] or (t == "LFG" and "Any" or "Warlock")
        db.place[t] = db.place[t] or ""
        db.lmin, db.lmax = db.lmin or {}, db.lmax or {}
        db.lmin[t] = db.lmin[t] or ""
        db.lmax[t] = db.lmax[t] or ""
        db.sent[t] = db.sent[t] or {}
        db.results[t] = db.results[t] or {}
    end
    return db
end

-- who filter string, or nil + reason
-- level range text -> (min, max) numbers or nils; blank = no limit
function ns.LevelRange(lmin, lmax)
    local a, b = tonumber(trim(lmin)), tonumber(trim(lmax))
    if a and b and a > b then a, b = b, a end
    return a, b
end

function ns.BuildFilter(class, place, lmin, lmax)
    local parts = {}
    local a, b = ns.LevelRange(lmin, lmax)
    if a or b then parts[#parts + 1] = (a or 1) .. "-" .. (b or 99) end
    if class and class ~= "Any" and class ~= "" then parts[#parts + 1] = 'c-"' .. class .. '"' end
    place = trim((tostring(place or ""):gsub('"', "")))
    if place ~= "" then parts[#parts + 1] = 'z-"' .. place .. '"' end
    if #parts == 0 then return nil, "Pick a class or type a place first." end
    return table.concat(parts, " ")
end

-- ---- sent marks ----
function ns.IsSent(tab, name)
    local t = ns.GetDB().sent[tab][name]
    if not t then return false end
    if ns.clock() - t >= ns.MARK_TTL then
        ns.GetDB().sent[tab][name] = nil
        return false
    end
    return true
end
function ns.MarkSent(tab, name)
    ns.GetDB().sent[tab][name] = ns.clock()
    if ns.offline then ns.offline[tab][name] = nil end
end

-- ---- offline replies ----
-- The server answers a whisper to an absent player with a system line
-- ("No player named 'X' is currently playing."). Un-mark that person and flag them offline.
ns.offline = { Going = {}, Stay = {}, LFG = {} }
ns.OFFLINE_WINDOW = 30 -- seconds after a whisper in which a "not found" reply is attributed to it
local function offlinePattern()
    local fmt = _G.ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
    local p = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)")
    return "^" .. p .. "$"
end
function ns.IsOffline(tab, name) return ns.offline[tab][name] and true or false end
-- returns the name if the message was a not-found reply that matched a recent whisper
function ns.OnSystemMessage(msg)
    if type(msg) ~= "string" then return nil end
    local name = msg:match(offlinePattern())
    if not name then return nil end
    local lname, hit = name:lower(), nil
    for _, tab in ipairs(ns.TABS) do
        for n, t in pairs(ns.GetDB().sent[tab]) do
            if n:lower() == lname and ns.clock() - t <= ns.OFFLINE_WINDOW then
                ns.GetDB().sent[tab][n] = nil
                ns.offline[tab][n] = true
                hit = n
            end
        end
    end
    if hit and ns.onOffline then ns.onOffline(hit) end
    return hit
end

function ns.ClearMarks(tab)
    if tab then ns.GetDB().sent[tab] = {} else for _, t in ipairs(ns.TABS) do ns.GetDB().sent[t] = {} end end
end

-- ---- search ----
local pending -- { cb = fn, id = n }
local searchId = 0

local function sortResults(list)
    table.sort(list, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return a.name < b.name
    end)
end

function ns.OnWhoEvent()
    if not pending then return end
    local cb = pending.cb
    pending = nil
    local n = C_FriendList.GetNumWhoResults() or 0
    local list = {}
    for i = 1, n do
        local info = C_FriendList.GetWhoInfo(i)
        if info and info.fullName then
            list[#list + 1] = { name = info.fullName, level = info.level, area = info.area or "", class = info.classStr or "" }
        end
    end
    sortResults(list)
    cb(list, n >= ns.WHO_CAP and "List cut at " .. ns.WHO_CAP .. " players - narrow the place." or nil)
end

-- cb(list, note) on success, cb(nil, errorText) on failure
function ns.Search(class, place, lmin, lmax, cb)
    local filter, why = ns.BuildFilter(class, place, lmin, lmax)
    if not filter then cb(nil, why); return end
    searchId = searchId + 1
    local id = searchId
    local a, b = ns.LevelRange(lmin, lmax)
    -- also filter here in case the game ignores the level part of the query
    pending = { id = id, cb = function(list, note)
        if list and (a or b) then
            local kept = {}
            for _, p in ipairs(list) do
                local lv = p.level or 0
                if lv >= (a or 0) and lv <= (b or 999) then kept[#kept + 1] = p end
            end
            list = kept
        end
        cb(list, note)
    end }
    local ok, err = pcall(C_FriendList.SendWho, filter)
    if not ok then pending = nil; cb(nil, "Search failed: " .. tostring(err)); return end
    C_Timer.After(ns.WHO_TIMEOUT, function()
        if pending and pending.id == id then
            pending = nil
            cb(nil, "No reply. The game limits searches - wait about 30 seconds and try again.")
        end
    end)
end

-- ---- sender ----
local sending -- { cancel = bool }

function ns.IsSending() return sending ~= nil end
function ns.StopSend() if sending then sending.cancel = true end end

-- names: array of player names. Returns count queued, or nil + reason.
function ns.StartSend(tab, names, text, onProgress, onDone)
    if sending then return nil, "Already sending." end
    text = trim(text)
    if text == "" then return nil, "Message is empty." end
    if #text > 255 then return nil, "Message is longer than 255 characters." end
    local queue = {}
    for _, n in ipairs(names) do
        if not ns.IsSent(tab, n) then queue[#queue + 1] = n end
    end
    if #queue == 0 then return nil, "Nobody to send to (none ticked, or already whispered recently)." end
    local state = { cancel = false }
    sending = state
    local sent, failed = 0, 0
    local function step(i)
        if state.cancel then
            sending = nil; onDone(sent, failed, true); return
        end
        local name = queue[i]
        local ok = pcall(C_ChatInfo.SendChatMessage, text, "WHISPER", nil, name)
        if ok then sent = sent + 1; ns.MarkSent(tab, name); ns.ticked[tab][name] = nil else failed = failed + 1 end
        onProgress(i, #queue, name, ok)
        if i >= #queue then
            sending = nil; onDone(sent, failed, false)
        else
            C_Timer.After(ns.SEND_GAP, function() step(i + 1) end)
        end
    end
    step(1)
    return #queue
end

-- ---- events ----
local f = CreateFrame("Frame")
f:RegisterEvent("WHO_LIST_UPDATE")
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:SetScript("OnEvent", function(_, event, msg)
    if event == "CHAT_MSG_SYSTEM" then ns.OnSystemMessage(msg) else ns.OnWhoEvent() end
end)
