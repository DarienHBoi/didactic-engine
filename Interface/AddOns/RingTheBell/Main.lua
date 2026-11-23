-- Ring the Bell: events. Reads the damage meter after each fight, keeps the shared record, syncs over hidden GUILD addon messages.
local addonName, RB = ...
local L, W, C = RB.L, RB.W, RB.C

if RB.onRecord == nil then RB.onRecord = function() end end  -- the UI (Banner.lua) replaces this

local savedTarget
local firstWorld = true
local lastQReply   -- GetTime() of the last accepted Q (replies are rate limited)
local Q_REPLY_GAP = 30
local pendingReplies = {}  -- Q replies waiting for their timer; { skip = bool }

-- Sending ------------------------------------------------------------------------------------------------------------
local function send(msg)
    if not msg or not C_ChatInfo or not IsInGuild() then return end
    C_ChatInfo.SendAddonMessage(W.PREFIX, msg, "GUILD")
end

pcall(function() C_ChatInfo.RegisterAddonMessagePrefix(W.PREFIX) end)

-- Version ------------------------------------------------------------------------------------------------------------
-- Read once at load; the fallback is the pre-C_AddOns global.
do
    local ver
    local ok, v = pcall(function() return C_AddOns.GetAddOnMetadata("RingTheBell", "Version") end)
    if ok and type(v) == "string" and v ~= "" then ver = v end
    if not ver then
        ok, v = pcall(function() return GetAddOnMetadata("RingTheBell", "Version") end)
        if ok and type(v) == "string" and v ~= "" then ver = v end
    end
    RB.version = ver or "0"
end
local shownVersions = {}  -- newer versions already bannered this session
local pushCooling = false
local PUSH_COOLDOWN = 30

function RB.pushUpdate()
    if pushCooling then return end
    if not IsInGuild() then
        print("Ring the Bell: not in a guild")
        return
    end
    send(W.encodeVersion(RB.version, true))
    print("Ring the Bell: pushed version " .. RB.version .. " to online guild members")
    pushCooling = true
    if RB.Board and RB.Board.setPushEnabled then RB.Board.setPushEnabled(false) end
    C_Timer.After(PUSH_COOLDOWN, function()
        pushCooling = false
        if RB.Board and RB.Board.setPushEnabled then RB.Board.setPushEnabled(true) end
    end)
end

-- Damage meter -------------------------------------------------------------------------------------------------------
-- Fight length in whole seconds (1..86400) from the Current session, or nil. Never raises.
local function sessionSeconds(session, DM, st)
    local function clamp(v)
        if not L.isNum(v) then return nil end
        v = math.floor(v)
        if v < 1 then return nil end
        return math.min(v, 86400)
    end
    local ok, v = pcall(function() return session.durationSeconds end)
    local s = ok and clamp(v) or nil
    if s then return s end
    ok, v = pcall(function() return DM.GetSessionDurationSeconds(st) end)
    return ok and clamp(v) or nil
end

-- Own player's combatSpells from the Current DamageDone session, or nil (missing meter, error, no own row).
-- Second result: the fight length in seconds (nil when unknown).
function RB.readMeter()
    local ok, rows, secs = pcall(function()
        local DM = C_DamageMeter
        if not DM then return nil end
        local st, mt = Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone
        local session = DM.GetCombatSessionFromType(st, mt)
        if type(session) ~= "table" or type(session.combatSources) ~= "table" then return nil end
        local guid
        for _, src in ipairs(session.combatSources) do
            if type(src) == "table" and not L.isSecret(src.isLocalPlayer) and src.isLocalPlayer == true then
                guid = src.sourceGUID
                break
            end
        end
        if L.isSecret(guid) or guid == nil then return nil end
        local data = DM.GetCombatSessionSourceFromType(st, mt, guid)
        if type(data) ~= "table" or type(data.combatSpells) ~= "table" then return nil end
        return data.combatSpells, sessionSeconds(session, DM, st)
    end)
    if ok then return rows, secs end
    return nil
end

local function plainString(s)
    if type(s) == "string" and not L.isSecret(s) and s ~= "" then return s end
    return nil
end

local function spellNameFor(id)
    local ok, name = pcall(function() return C_Spell.GetSpellName(id) end)
    name = ok and plainString(name) or nil
    if name then return name end
    return "Spell " .. (L.isNum(id) and tostring(id) or "?")
end

local function ownClass()
    local ok, c = pcall(function() return select(2, UnitClass("player")) end)
    return ok and L.validClass(c) or nil
end

local function afterFight(fightTarget)
    local db = RB.db
    if not db then return end
    local rows, secs = RB.readMeter()
    local best = C.bestSpell(rows)
    if not best then return end
    local id = L.isNum(best.spellID) and best.spellID or nil
    local t = GetServerTime()
    local rec = {
        amount = math.floor(best.totalAmount),
        spellID = id,
        spell = spellNameFor(id),
        target = plainString(best.creatureName) or fightTarget or "?",
        player = RB.me,
        t = t,
        class = ownClass(),
        secs = secs,
    }
    rec.id = L.newId(rec.player, rec.t, rec.amount)
    if not L.beats(rec, db.record) then return end
    local prev = db.record
    L.merge(db, rec)
    send(W.encode("C", rec))
    RB.onRecord(rec, prev, true)
end

-- Sync ---------------------------------------------------------------------------------------------------------------
local function replyToQ()
    local db = RB.db
    if not db or not db.record then return end
    local now = GetTime()
    if lastQReply and now - lastQReply < Q_REPLY_GAP then return end
    lastQReply = now
    local pending = { skip = false }
    pendingReplies[#pendingReplies + 1] = pending
    C_Timer.After(math.random() * 3, function()
        for i, p in ipairs(pendingReplies) do
            if p == pending then table.remove(pendingReplies, i) break end
        end
        local rec = db.record
        if pending.skip or not rec then return end
        send(W.encode("R", rec))
        local n = 0
        for _, h in ipairs(db.history or {}) do
            if n >= 5 then break end
            if h.id ~= rec.id then
                send(W.encode("R", h))
                n = n + 1
            end
        end
    end)
end

local function refreshBoard()
    if RB.Board and RB.Board.refresh then pcall(RB.Board.refresh) end
end

local function onAddon(prefix, msg, channel, sender)
    local db = RB.db
    if not db or not RB.me then return end
    if L.isSecret(prefix) or L.isSecret(msg) or L.isSecret(channel) or L.isSecret(sender) then return end
    if prefix ~= W.PREFIX or channel ~= "GUILD" then return end
    local who = L.normName(sender, RB.realm)
    if not who or L.sameName(who, RB.me) then return end
    local kind, rec = W.decode(msg)
    if kind == "C" then
        local prev = db.record
        local changed = L.merge(db, rec)
        if db.record == rec then RB.onRecord(rec, prev, false) end
        if changed then refreshBoard() end
        if db.record ~= rec and L.beats(db.record, rec) then replyToQ() end
    elseif kind == "R" then
        if db.record and rec.amount >= db.record.amount then
            for _, p in ipairs(pendingReplies) do p.skip = true end
        end
        if L.merge(db, rec) then refreshBoard() end
        if L.beats(db.record, rec) then replyToQ() end
    elseif kind == "Q" then
        replyToQ()
    elseif kind == "V" then
        if L.versionNewer(rec.version, RB.version) and (rec.push or not shownVersions[rec.version]) then
            shownVersions[rec.version] = true
            if RB.Banner and RB.Banner.showUpdate then RB.Banner.showUpdate(who, rec.version, RB.version) end
        end
    end
end

-- Events -------------------------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD" }) do
    pcall(frame.RegisterEvent, frame, ev)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end
        RingTheBellDB = L.sanitize(RingTheBellDB)
        RB.db = RingTheBellDB
        RB.realm = GetRealmName()
        RB.me = L.normName(UnitName("player"), RB.realm)
    elseif event == "PLAYER_REGEN_DISABLED" then
        savedTarget = nil
        pcall(function() savedTarget = plainString(UnitName("target")) end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        local fightTarget = savedTarget
        C_Timer.After(1.5, function()
            -- a new fight started meanwhile: the meter's Current session has rolled over, so the read would be partial
            if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
            pcall(afterFight, fightTarget)
        end)
    elseif event == "CHAT_MSG_ADDON" then
        onAddon(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitial, isReload = ...
        local login = firstWorld
        if isInitial ~= nil or isReload ~= nil then login = firstWorld and isInitial == true end
        firstWorld = false
        if login then
            C_Timer.After(5, function()
                send(W.encode("Q"))
                send(W.encodeVersion(RB.version, false))
            end)
        end
    end
end)

-- Slash --------------------------------------------------------------------------------------------------------------
SLASH_RINGTHEBELL1 = "/bell"
SlashCmdList = SlashCmdList or {}
SlashCmdList["RINGTHEBELL"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$"):lower()
    if msg == "probe" then
        if RB.Probe and RB.Probe.run then RB.Probe.run() end
    elseif RB.Board and RB.Board.toggle then
        RB.Board.toggle()
    else
        local rec = RB.db and RB.db.record
        if rec then
            print(string.format("Ring the Bell: record %d (%s on %s, by %s)", rec.amount, tostring(rec.spell), tostring(rec.target), tostring(rec.player)))
        else
            print("Ring the Bell: no record yet")
        end
    end
end
