-- TaxiSpike: throwaway test. Proves /who and whispers work from an addon.
local function say(...)
    print("|cff66ccffTaxiSpike|r", ...)
end

local function has(path)
    local ok, v = pcall(function()
        local t = _G
        for part in string.gmatch(path, "[^%.]+") do
            if type(t) ~= "table" then return nil end
            t = t[part]
        end
        return t
    end)
    return ok and v ~= nil
end

local function send(target, text)
    local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    return pcall(fn, text, "WHISPER", nil, target)
end

local pendingWho
local f = CreateFrame("Frame")
f:RegisterEvent("WHO_LIST_UPDATE")
f:SetScript("OnEvent", function()
    if not pendingWho then return end
    pendingWho = nil
    local n = 0
    if C_FriendList and C_FriendList.GetNumWhoResults then
        n = C_FriendList.GetNumWhoResults()
    elseif GetNumWhoResults then
        n = GetNumWhoResults()
    end
    say("who results:", n)
    for i = 1, math.min(n, 10) do
        local info
        if C_FriendList and C_FriendList.GetWhoInfo then
            info = C_FriendList.GetWhoInfo(i)
        end
        if info then
            say(i, info.fullName or info.name, info.level, info.area, info.classStr or info.filename)
        else
            say(i, "(no info)")
        end
    end
end)

local function doWho(class, zone)
    local filter = 'c-"' .. class .. '" z-"' .. zone .. '"'
    pendingWho = true
    local ok, err
    if C_FriendList and C_FriendList.SendWho then
        ok, err = pcall(C_FriendList.SendWho, filter)
    elseif SendWho then
        ok, err = pcall(SendWho, filter)
    else
        say("no SendWho API found"); pendingWho = nil; return
    end
    say("sent who:", filter, ok and "ok" or ("ERROR " .. tostring(err)))
    C_Timer.After(5, function()
        if pendingWho then
            pendingWho = nil
            say("no WHO_LIST_UPDATE after 5s")
        end
    end)
end

SLASH_TAXISPIKE1 = "/txs"
SlashCmdList["TAXISPIKE"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    if cmd == "api" then
        for _, p in ipairs({
            "C_FriendList.SendWho", "C_FriendList.GetNumWhoResults",
            "C_FriendList.GetWhoInfo", "C_ChatInfo.SendChatMessage",
            "SendChatMessage", "C_Timer.After",
        }) do
            say(p, has(p) and "YES" or "no")
        end
    elseif cmd == "find" then
        -- list global names (and C_ table members) containing the pattern
        local pat = rest:lower()
        if pat == "" then say("usage: /txs find <text>"); return end
        local out = {}
        for k, v in pairs(_G) do
            if type(k) == "string" then
                if k:lower():find(pat, 1, true) and (type(v) == "function" or type(v) == "table") then
                    out[#out + 1] = k
                end
                if k:sub(1, 2) == "C_" and type(v) == "table" then
                    for k2, v2 in pairs(v) do
                        if type(k2) == "string" and type(v2) == "function" and k2:lower():find(pat, 1, true) then
                            out[#out + 1] = k .. "." .. k2
                        end
                    end
                end
            end
        end
        table.sort(out)
        say(#out, "matches for", rest)
        for i = 1, math.min(#out, 40) do say(out[i]) end
    elseif cmd == "dump" then
        local t = _G[rest]
        if type(t) ~= "table" then say(rest, "is", type(t)); return end
        local out = {}
        for k, v in pairs(t) do
            if type(k) == "string" then out[#out + 1] = k .. ":" .. type(v) end
        end
        table.sort(out)
        say(rest, #out, "string keys")
        for i = 1, math.min(#out, 60) do say(out[i]) end
    elseif cmd == "who" then
        local class, zone = rest:match("^(%S+)%s+(.+)$")
        if not class then say("usage: /txs who <Class> <Zone>"); return end
        doWho(class, zone)
    elseif cmd == "w" then
        local name, text = rest:match("^(%S+)%s+(.+)$")
        if not name then say("usage: /txs w <name> <text>"); return end
        local ok, err = send(name, text)
        say("whisper to", name, ok and "sent (check chat for errors)" or ("ERROR " .. tostring(err)))
    elseif cmd == "chain" then
        local names, text = rest:match("^(%S+)%s+(.+)$")
        if not names then say("usage: /txs chain <n1,n2,..> <text>"); return end
        local list = {}
        for n in string.gmatch(names, "[^,]+") do list[#list + 1] = n end
        for i, n in ipairs(list) do
            C_Timer.After((i - 1) * 1.5, function()
                local ok, err = send(n, text)
                say("chain", i .. "/" .. #list, n, ok and "sent" or ("ERROR " .. tostring(err)))
            end)
        end
    else
        say("/txs api | who <Class> <Zone> | w <name> <text> | chain <n1,n2> <text>")
    end
end

-- /txs probe: gathers everything to TaxiSpikeDB.log (read from disk after /reload or logout)
local function plog(s)
    TaxiSpikeDB = TaxiSpikeDB or {}
    TaxiSpikeDB.log = TaxiSpikeDB.log or {}
    TaxiSpikeDB.log[#TaxiSpikeDB.log + 1] = s
end

local function dumpTable(name, t)
    if type(t) ~= "table" then plog(name .. " = " .. type(t)); return end
    local out = {}
    for k, v in pairs(t) do
        local tv = type(v)
        local val = (tv == "number" or tv == "string" or tv == "boolean") and ("=" .. tostring(v)) or ""
        out[#out + 1] = tostring(k) .. ":" .. tv .. val
    end
    table.sort(out)
    plog("DUMP " .. name .. " (" .. #out .. ")")
    for _, line in ipairs(out) do plog("  " .. line) end
end

local function findNames(pat)
    local out = {}
    for k, v in pairs(_G) do
        if type(k) == "string" then
            if k:lower():find(pat, 1, true) and (type(v) == "function" or type(v) == "table") then out[#out + 1] = k end
            if k:sub(1, 2) == "C_" and type(v) == "table" then
                for k2, v2 in pairs(v) do
                    if type(k2) == "string" and type(v2) == "function" and k2:lower():find(pat, 1, true) then
                        out[#out + 1] = k .. "." .. k2
                    end
                end
            end
        end
    end
    table.sort(out)
    plog("FIND " .. pat .. " (" .. #out .. "): " .. table.concat(out, ", "))
end

local whoEvents = 0
local pf = CreateFrame("Frame")
pf:RegisterEvent("WHO_LIST_UPDATE")
pf:SetScript("OnEvent", function()
    whoEvents = whoEvents + 1
end)

local filters = {
    'c-"Warlock" z-"Orgrimmar"',
    'c-"Warlock"',
    'z-"Orgrimmar"',
    'Warlock',
    '1-20 c-"Warlock"',
    'c-"Warlock" z-"Durotar"',
}

local function runProbe()
    TaxiSpikeDB = { log = {} }
    plog("PROBE start " .. date("%Y-%m-%d %H:%M:%S"))
    local _, _, _, build = GetBuildInfo()
    plog("build " .. tostring(build))
    for _, n in ipairs({ "LFGWhoListFrame", "LFGWhoListFilterUtil", "LFGWhoListButtonMixin", "LFGVanillaWhoListTabButtonMixin" }) do
        dumpTable(n, _G[n])
    end
    for _, p in ipairs({ "who", "lfg", "playersearch", "lookingforgroup" }) do findNames(p) end
    if C_FriendList then dumpTable("C_FriendList", C_FriendList) end
    local i = 0
    local function step()
        i = i + 1
        if i > #filters then
            plog("PROBE done " .. date("%H:%M:%S") .. " - now /reload to save")
            say("probe done: /reload now, then tell Claude")
            return
        end
        local filter = filters[i]
        local before = whoEvents
        local ok, err = pcall(C_FriendList.SendWho, filter)
        C_Timer.After(6, function()
            local n = C_FriendList.GetNumWhoResults and C_FriendList.GetNumWhoResults() or -1
            local first = ""
            local info = n > 0 and C_FriendList.GetWhoInfo(1)
            if info then first = tostring(info.fullName) .. " L" .. tostring(info.level) .. " " .. tostring(info.area) end
            plog(("WHO [%s] ok=%s err=%s events=%d results=%d first=%s"):format(
                filter, tostring(ok), tostring(err), whoEvents - before, n, first))
            step()
        end)
    end
    step()
end

local old = SlashCmdList["TAXISPIKE"]
SlashCmdList["TAXISPIKE"] = function(msg)
    if msg:match("^probe") then
        say("probe running (about 40s)...")
        runProbe()
    else
        old(msg)
    end
end
