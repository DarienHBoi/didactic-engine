-- Ring the Bell probe (phase 0): learn whether UNIT_COMBAT amounts are secret in combat and which fields
-- C_DamageMeter spell entries expose. Out of combat: /bell probe. Results land in RingTheBellDB.probe.
local addonName, RB = ...
RB = RB or {}

local P = { state = { unitCombatSecret = nil } }
RB.Probe = P

local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, r = pcall(issecretvalue, v)
    return (ok and r) and true or false
end

local function str(v)
    if isSecret(v) then return "<secret>" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<error>"
end

local function keys(t)
    local out = {}
    if type(t) ~= "table" then return out end
    for k in pairs(t) do
        if not isSecret(k) then out[#out + 1] = str(k) end
    end
    table.sort(out)
    return out
end

local function addSample(sample, t, prefix)
    for _, k in ipairs(keys(t)) do
        local ok, v = pcall(function() return t[k] end)
        if ok and (isSecret(v) or type(v) ~= "table") then sample[prefix .. k] = str(v)
        elseif ok then sample[prefix .. k] = "<table>" end
    end
end

local function count(t)
    if type(t) ~= "table" then return -1 end
    local ok, n = pcall(function() return #t end)
    return ok and n or -2
end

-- My row: isLocalPlayer == true, else sourceGUID equal to UnitGUID("player") (both readable).
local function findMine(session)
    if type(session) ~= "table" or type(session.combatSources) ~= "table" then return nil end
    local me = UnitGUID and UnitGUID("player")
    for _, row in ipairs(session.combatSources) do
        if type(row) == "table" and row.isLocalPlayer == true then return row, "isLocalPlayer" end
    end
    if me and not isSecret(me) then
        for _, row in ipairs(session.combatSources) do
            local g = type(row) == "table" and row.sourceGUID
            if g and not isSecret(g) and g == me then return row, "guid" end
        end
    end
    return nil
end

-- Returns a table of findings, or nil + reason.
function P.dumpMeter()
    P.lastDiag = {}
    if not C_DamageMeter then return nil, "no C_DamageMeter" end
    local E = Enum and Enum.DamageMeterSessionType
    local MT = Enum and Enum.DamageMeterType
    if not (E and MT) then return nil, "no Enum.DamageMeter*" end
    local ok, res, why = pcall(function()
        local diag = P.lastDiag
        local sessionName, session, mine, how, getSource = nil, nil, nil, nil, nil
        for _, name in ipairs({ "Current", "Overall" }) do
            local s = C_DamageMeter.GetCombatSessionFromType(E[name], MT.DamageDone)
            local row, h = findMine(s)
            diag[#diag + 1] = name .. ": sources=" .. count(s and s.combatSources) .. (row and (" mine by " .. h) or "")
            if s and not diag.firstRowFields and type(s.combatSources) == "table" and type(s.combatSources[1]) == "table" then
                diag.firstRowFields = keys(s.combatSources[1])
                diag.firstRowSample = {}
                addSample(diag.firstRowSample, s.combatSources[1], "")
            end
            if row then
                sessionName, session, mine, how = name, s, row, h
                getSource = function(guid) return C_DamageMeter.GetCombatSessionSourceFromType(E[name], MT.DamageDone, guid) end
                break
            end
        end
        if not mine and C_DamageMeter.GetAvailableCombatSessions then
            local list = C_DamageMeter.GetAvailableCombatSessions()
            diag[#diag + 1] = "available: n=" .. count(list)
            local last = type(list) == "table" and list[count(list)]
            if type(last) == "table" then
                diag.availableFields = keys(last)
                local id = last.sessionID or last.combatSessionID or last.id
                if id ~= nil and not isSecret(id) and C_DamageMeter.GetCombatSessionFromID then
                    local s = C_DamageMeter.GetCombatSessionFromID(id, MT.DamageDone)
                    local row, h = findMine(s)
                    diag[#diag + 1] = "byID " .. str(id) .. ": sources=" .. count(s and s.combatSources) .. (row and (" mine by " .. h) or "")
                    if row then
                        sessionName, session, mine, how = "ID " .. str(id), s, row, h
                        getSource = function(guid) return C_DamageMeter.GetCombatSessionSourceFromID(id, MT.DamageDone, guid) end
                    end
                end
            end
        end
        if not mine then return nil, "local player row not found" end
        local data = getSource(mine.sourceGUID)
        if type(data) ~= "table" then return nil, "no source data" end
        local out = {
            session = sessionName, mineBy = how,
            sessionFields = keys(session), sourceFields = keys(mine), sourceDataFields = keys(data),
            spellFields = {}, detailFields = {}, sample = {}, spellCount = 0,
        }
        out.sourceDataSample = {}
        addSample(out.sourceDataSample, data, "")
        out.sessionSample = {}
        addSample(out.sessionSample, session, "")
        out.spellTotals = {}
        local spells = data.combatSpells
        if type(spells) == "table" then
            local seenS, seenD = {}, {}
            for i, sp in ipairs(spells) do
                out.spellCount = out.spellCount + 1
                if type(sp) == "table" then
                    out.spellTotals[#out.spellTotals + 1] = str(sp.spellID) .. "=" .. str(sp.totalAmount) .. " casts " .. tostring(P.state.casts and not isSecret(sp.spellID) and P.state.casts[sp.spellID] or 0)
                end
                for _, k in ipairs(keys(sp)) do seenS[k] = true end
                local det = type(sp) == "table" and sp.combatSpellDetails
                if type(det) == "table" and type(det[1]) == "table" then det = det[1] end
                if type(det) == "table" then for _, k in ipairs(keys(det)) do seenD[k] = true end end
                if i == 1 then
                    addSample(out.sample, sp, "")
                    if type(det) == "table" then addSample(out.sample, det, "detail.") end
                end
            end
            out.spellFields = keys(seenS)
            out.detailFields = keys(seenD)
        end
        return out
    end)
    if not ok then return nil, "error: " .. str(res) end
    return res, why
end

function P.onCast(unit, _, spellID)
    if unit ~= "player" or spellID == nil or isSecret(spellID) then return end
    local S = P.state
    S.casts = S.casts or {}
    S.casts[spellID] = (S.casts[spellID] or 0) + 1
end

function P.onUnitCombat(unit, action, _, amount)
    local S = P.state
    S.events = (S.events or 0) + 1
    if action == "WOUND" then S.wounds = (S.wounds or 0) + 1 end
    if unit ~= "target" or action ~= "WOUND" then return end
    S.targetWounds = (S.targetWounds or 0) + 1
    S.kept = S.kept or {}
    if #S.kept < 5 then S.kept[#S.kept + 1] = amount end  -- v5: does a hit kept from combat turn readable afterwards?
    if isSecret(amount) then
        S.unitCombatSecret = true; P.widgetTest(amount)
    elseif S.unitCombatSecret == nil then S.unitCombatSecret = false end
end

-- v4: workarounds for secret hit amounts --------------------------------------------------------------
-- (a) server statistics whose name mentions a hit or crit (e.g. "Largest hit dealt"), read out of combat
function P.scanStats()
    local out = { has = {} }
    for _, fn in ipairs({ "GetStatistic", "GetStatisticsCategoryList", "GetCategoryNumAchievements", "GetAchievementInfo" }) do
        out.has[fn] = type(_G[fn]) == "function"
    end
    if not (out.has.GetStatistic and out.has.GetStatisticsCategoryList and out.has.GetCategoryNumAchievements and out.has.GetAchievementInfo) then
        return out
    end
    local ok, err = pcall(function()
        local cats = GetStatisticsCategoryList()
        out.categories = type(cats) == "table" and #cats or -1
        out.found = {}
        for _, cat in ipairs(type(cats) == "table" and cats or {}) do
            local n = GetCategoryNumAchievements(cat) or 0
            if not isSecret(n) and type(n) == "number" then
                for i = 1, n do
                    local id, name = GetAchievementInfo(cat, i)
                    if type(name) == "string" and not isSecret(name) then
                        local low = name:lower()
                        if low:find("hit") or low:find("crit") or low:find("largest") or low:find("highest") then
                            out.found[#out.found + 1] = str(id) .. " " .. name .. " = " .. str(GetStatistic(id))
                        end
                    end
                end
            end
        end
    end)
    if not ok then out.err = str(err) end
    return out
end

-- (b) old-style self damage chat / combat text events: can they register, do they fire, is the text readable
P.alt = { reg = {}, fired = {}, samples = {} }
P.ALT_EVENTS = { "CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
    "COMBAT_TEXT_UPDATE", "CHAT_MSG_COMBAT_MISC_INFO" }
function P.onAlt(event, ...)
    local A = P.alt
    A.fired[event] = (A.fired[event] or 0) + 1
    if #A.samples < 6 then
        local a1, a2, a3 = ...
        A.samples[#A.samples + 1] = event .. ": " .. str(a1) .. " | " .. str(a2) .. " | " .. str(a3)
    end
end

-- (c) read a secret hit back through widget geometry (first 3 secret hits only)
P.widget = { tries = 0, results = {} }
function P.widgetTest(amount)
    local Wd = P.widget
    if Wd.tries >= 3 or not CreateFrame then return end
    Wd.tries = Wd.tries + 1
    pcall(function()
        if not Wd.bar then
            Wd.bar = CreateFrame("StatusBar", nil, UIParent)
            Wd.bar:SetSize(1000, 4); Wd.bar:SetPoint("TOP", UIParent, "BOTTOM", 0, -50); Wd.bar:SetAlpha(0)
            Wd.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8"); Wd.bar:SetMinMaxValues(0, 100000)
            Wd.fs = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal"); Wd.fs:SetAlpha(0)
            Wd.fs:SetPoint("TOP", UIParent, "BOTTOM", 0, -80)
        end
        local okV = pcall(Wd.bar.SetValue, Wd.bar, amount)
        local okT = pcall(Wd.fs.SetText, Wd.fs, amount)
        local function read()
            local r = { setValue = okV, setText = okT }
            local ok1, v = pcall(Wd.bar.GetValue, Wd.bar); r.getValue = ok1 and str(v) or "<error>"
            local tex = Wd.bar:GetStatusBarTexture()
            local ok2, w = pcall(tex.GetWidth, tex); r.fillWidth = ok2 and str(w) or "<error>"
            local ok3, sw = pcall(Wd.fs.GetStringWidth, Wd.fs); r.textWidth = ok3 and str(sw) or "<error>"
            local ok4, t = pcall(Wd.fs.GetText, Wd.fs); r.getText = ok4 and str(t) or "<error>"
            Wd.results[#Wd.results + 1] = r
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.1, read) else read() end
    end)
end

local function say(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100RTB|r " .. msg)
    else print("RTB " .. msg) end
end

local function join(t) return #t > 0 and table.concat(t, ",") or "(none)" end

-- v5: check the hits kept during combat; label = when (e.g. "2s", "10s" after combat)
function P.checkKept(label)
    local S = P.state
    S.keptCheck = S.keptCheck or {}
    local parts = {}
    for _, v in ipairs(S.kept or {}) do parts[#parts + 1] = str(v) end
    S.keptCheck[#S.keptCheck + 1] = label .. ": " .. (#parts > 0 and table.concat(parts, ",") or "(none kept)")
end

function P.run(quiet)
    if InCombatLockdown and InCombatLockdown() then if not quiet then say("leave combat first") end return end
    local r, why = P.dumpMeter()
    RingTheBellDB = RingTheBellDB or {}
    local old = RingTheBellDB.probe
    if quiet and not r and type(old) == "table" and old.spellFields then return end  -- keep an earlier good read
    local saved = r or {}
    saved.unitCombatSecret = P.state.unitCombatSecret
    saved.reason = (not r) and why or nil
    saved.apiFields = keys(C_DamageMeter)
    saved.meterTypes = keys(Enum and Enum.DamageMeterType)
    saved.diag = P.lastDiag
    saved.stats = P.scanStats()
    saved.alt = P.alt
    saved.widget = P.widget.results
    saved.keptCheck = P.state.keptCheck
    saved.events, saved.wounds, saved.targetWounds = P.state.events, P.state.wounds, P.state.targetWounds
    if C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable then
        local ok, v = pcall(C_DamageMeter.IsDamageMeterAvailable)
        saved.meterAvailable = ok and str(v) or "<error>"
    end
    RingTheBellDB.probe = saved
    if quiet then say("probe saved after combat (" .. (r and "meter ok" or tostring(why)) .. "); /reload to write") return end
    if not r then say("meter: " .. tostring(why) .. " | " .. table.concat(P.lastDiag or {}, "; ")) end
    say("UNIT_COMBAT events " .. tostring(P.state.events) .. ", wounds " .. tostring(P.state.wounds) .. ", on target " .. tostring(P.state.targetWounds))
    say("api: " .. join(saved.apiFields))
    say("meterTypes: " .. join(saved.meterTypes))
    say("unitCombatSecret: " .. tostring(P.state.unitCombatSecret))
    say("kept hits after combat: " .. join(P.state.keptCheck or {}))
    local st = saved.stats
    say("stats: " .. (st.found and (#st.found .. " found: " .. join(st.found)) or ("API missing " .. (st.err or ""))))
    for _, r in ipairs(saved.widget) do say("widget: value " .. r.getValue .. " fill " .. r.fillWidth .. " textW " .. r.textWidth .. " text " .. r.getText) end
    if r then
        say("session: " .. r.session .. " (mine by " .. tostring(r.mineBy) .. ") spells: " .. r.spellCount)
        say("sessionFields: " .. join(r.sessionFields))
        say("sourceFields: " .. join(r.sourceFields))
        say("sourceDataFields: " .. join(r.sourceDataFields))
        say("spellFields: " .. join(r.spellFields))
        say("detailFields: " .. join(r.detailFields))
        say("source maxAmount " .. tostring(r.sourceDataSample.maxAmount) .. ", totalAmount " .. tostring(r.sourceDataSample.totalAmount) .. " | spells: " .. join(r.spellTotals))
    end
    say("saved to RingTheBellDB.probe (/reload to write)")
end
