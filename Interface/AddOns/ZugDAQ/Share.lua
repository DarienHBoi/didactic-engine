local _, ns = ...

-- Fresh AH prices, shared live between guildmates in game.
--
-- Every price check ZugDAQ makes (an item's listings, cheapest first) goes out quietly on the guild's addon channel,
-- and every guildmate's ZugDAQ keeps the newest check of each item, whoever made it. So whoever's at the AH keeps the
-- whole guild's prices fresh: tooltips, the Sales plan and Buy & craft use them at once, no app needed.
--
-- The app gets them from the save, which the game only writes at /reload or logout. Because everyone online holds
-- everyone's prices, the first guildmate to /reload or log out (for any reason) carries them all to the app and the
-- guild's server. Closing the AH with fresh prices offers that reload as one click (or /zug send).
--
-- Message (one per item, under 255 bytes):  L;itemID;time;listed;price:qty,price:qty,...   (cheapest first)

local PREFIX = "ZugDAQ1"
local SEND_EVERY = 0.35       -- seconds between messages: well inside the game's addon message limits
local MAX_STEPS = 20          -- listings per message (cut to fit)
local FRESH = 15 * 60         -- a check younger than this isn't worth re-checking (anyone's)
local PROMPT_MIN = 5          -- fresh prices held before closing the AH offers to send them

local queue, queued, sending = {}, {}, false
ns.shared = { sent = 0, received = 0, from = {} }
local loginTime = time()

local function myName() return UnitName("player") end

local function encode(id, entry)
    local parts = { "L", tostring(id), tostring(entry.t or time()), tostring(entry.total or 0) }
    local head = table.concat(parts, ";") .. ";"
    local steps, len = {}, #head
    for i, l in ipairs(entry.listings or {}) do
        if i > MAX_STEPS then break end
        local s = string.format("%d:%d", l.price, l.qty or 1)
        if len + #s + 1 > 250 then break end
        steps[#steps + 1] = s
        len = len + #s + 1
    end
    return head .. table.concat(steps, ",")
end

local function decode(text)
    local kind, id, t, total, rest = text:match("^(%a);(%d+);(%d+);(%d+);(.*)$")
    if kind ~= "L" then return end
    local listings = {}
    for price, qty in (rest or ""):gmatch("(%d+):(%d+)") do
        listings[#listings + 1] = { price = tonumber(price), qty = tonumber(qty) }
    end
    return tonumber(id), { t = tonumber(t), total = tonumber(total), listings = listings }
end

local function sendNext()
    local id = table.remove(queue, 1)
    if not id then sending = false return end
    queued[id] = nil
    local entry = ns.db and ns.db.live and ns.db.live[id]
    if entry and not entry.by and IsInGuild and IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, encode(id, entry), "GUILD")
        if ok then ns.shared.sent = ns.shared.sent + 1 end
    end
    C_Timer.After(SEND_EVERY, sendNext)
end

-- a check of our own finished: tell the guild (once per check)
ns.Listen("LIVE_STORED", function(id)
    if not id or queued[id] then return end
    queued[id] = true
    queue[#queue + 1] = id
    if not sending then
        sending = true
        C_Timer.After(SEND_EVERY, sendNext)
    end
end)

ns.OnLogin(function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    -- the guild's checks the app passed on (from the server's pool): any newer than ours, for people who weren't online
    local d = ns.AppData and ns.AppData()
    ns.db.live = ns.db.live or {}
    for id, p in pairs(d and d.pooled or {}) do
        local have = ns.db.live[id]
        if type(p) == "table" and p.t and (not have or (have.t or 0) < p.t) then
            local listings = {}
            for _, l in ipairs(p.l or {}) do listings[#listings + 1] = { price = l[1], qty = l[2] } end
            ns.db.live[id] = { t = p.t, total = p.total, listings = listings, by = (p.by ~= myName()) and p.by or nil, pooled = true }
        end
    end
end)

-- a guildmate's check: keep it when it's newer than what we have
ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= PREFIX or channel ~= "GUILD" or not ns.db then return end
    local who = Ambiguate and Ambiguate(sender or "", "none") or sender
    if who == myName() then return end
    local id, entry = decode(text or "")
    if not id or not entry.t then return end
    ns.db.live = ns.db.live or {}
    local have = ns.db.live[id]
    if have and (have.t or 0) >= entry.t then return end
    entry.by = who
    ns.db.live[id] = entry
    ns.shared.received = ns.shared.received + 1
    ns.shared.from[who] = (ns.shared.from[who] or 0) + 1
    ns.Debounce("guildprices", 1.5, function()
        ns.Fire("LIVE_PRICES", true)
        ns.RequestRefresh()
    end)
end)

--- Whether anyone (you or a guildmate) checked this item in the last 15 minutes.
function ns.RecentlyChecked(id)
    local e = ns.db and ns.db.live and ns.db.live[id]
    return e and e.t and time() - e.t < FRESH
end

--- Prices you hold that the app hasn't seen yet: checked (by anyone) since you last loaded the UI.
function ns.FreshPricesHeld()
    local n = 0
    for _, e in pairs(ns.db and ns.db.live or {}) do
        if (e.t or 0) >= loginTime then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------- one click to send them to the guild

local prompt
local function showPrompt(count)
    if not prompt then
        prompt = CreateFrame("Frame", "ZugDAQSendPrompt", UIParent, "BackdropTemplate")
        prompt:SetSize(330, 104)
        prompt:SetPoint("TOP", 0, -140)
        prompt:SetFrameStrata("DIALOG")
        ns.Backdrop(prompt, 0.05, 0.04, 0.03, 0.95)
        prompt.text = ns.Label(prompt, "GameFontHighlight", "", "CENTER")
        prompt.text:SetPoint("TOP", 0, -14)
        prompt.text:SetWidth(300)
        local send = ns.Button(prompt, "Send now (reload)", 140, function()
            if InCombatLockdown and InCombatLockdown() then ns.Print("not in combat: try again after.") return end
            ReloadUI()
        end)
        send:SetPoint("BOTTOMLEFT", 18, 14)
        local later = ns.Button(prompt, "Not now", 100, function() prompt:Hide() end)
        later:SetPoint("BOTTOMRIGHT", -18, 14)
        C_Timer.NewTicker(1, function()
            if prompt:IsShown() and prompt.until_ and GetTime() > prompt.until_ then prompt:Hide() end
        end)
    end
    prompt.text:SetText(string.format("|cffffd700ZugDAQ|r: you hold %d fresh AH price%s.\nSend them to the guild's app? It's a quick /reload.",
        count, count == 1 and "" or "s"))
    prompt.until_ = GetTime() + 30
    prompt:Show()
end

ns.On("AUCTION_HOUSE_CLOSED", function()
    if ns.settings and ns.settings.sendPrompt == false then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local n = ns.FreshPricesHeld()
    if n >= PROMPT_MIN then C_Timer.After(0.5, function() showPrompt(n) end) end
end)

--- /zug send: reload now so the app (and the guild) get the prices you hold.
function ns.SendCommand(rest)
    rest = strtrim(rest or "")
    if rest == "off" or rest == "on" then
        ns.settings.sendPrompt = rest == "on"
        ns.Print("the \"send prices to the guild\" offer on closing the AH is %s.", rest)
        return
    end
    if InCombatLockdown and InCombatLockdown() then ns.Print("not in combat: try again after.") return end
    ns.Print("sending %d fresh AH prices to the app: reloading.", ns.FreshPricesHeld())
    ReloadUI()
end
