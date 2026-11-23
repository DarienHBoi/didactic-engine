local _, ns = ...

-- Always-on activity tracking, kept in your own saved variables (nothing leaves your PC):
--   zones     per character and zone: time spent, coin and items looted, quest gold, kills, and what
--             each gathering skill gave there (all time, plus the last 30 days day by day)
--   gathering every herb, ore, skin and catch: when, where (map and position), skill and what it gave
--   character level, race, guild and every profession's skill level, read at login
-- ZugDAQ reads this to show where you make money and suggest where to farm.

local GATHER_LOG_MAX = 3000
local DAYS_KEPT = 30
local GATHER_WINDOW = 5 -- seconds between a gathering cast and its loot window

-- English spell names of the gathering skills (the casts that open a node or a corpse)
local GATHER_SPELLS = {
    ["Mining"] = "mining",
    ["Herb Gathering"] = "herbalism",
    ["Herbalism"] = "herbalism",
    ["Skinning"] = "skinning",
    ["Fishing"] = "fishing",
}

local function zoneName()
    local z = GetRealZoneText and GetRealZoneText()
    if not z or z == "" then z = GetZoneText and GetZoneText() or "Unknown" end
    return z
end

local function charZones()
    ns.db.zones = ns.db.zones or {}
    local c = ns.db.zones[ns.charKey]
    if not c then
        c = {}
        ns.db.zones[ns.charKey] = c
    end
    return c
end

-- the record for the current zone (and today's slice of it)
local function zoneRecord()
    local zones = charZones()
    local name = zoneName()
    local z = zones[name]
    if not z then
        z = { t = 0, coin = 0, quest = 0, kills = 0, items = {}, gathers = {}, days = {} }
        zones[name] = z
    end
    local today = ns.Today()
    local d = z.days[today]
    if not d then
        d = { t = 0, coin = 0, kills = 0, items = {}, gathers = {} }
        z.days[today] = d
    end
    return z, d
end

local function trimDays()
    local cutoff = ns.DayKey(time() - DAYS_KEPT * 86400)
    for _, zones in pairs(ns.db.zones or {}) do
        for _, z in pairs(zones) do
            for day in pairs(z.days or {}) do
                if day < cutoff then z.days[day] = nil end
            end
        end
    end
end

local function add(map, id, n)
    map[id] = (map[id] or 0) + n
end

-- ---------------------------------------------------------------- time spent per zone

local lastTick
C_Timer.NewTicker(30, function()
    if not ns.db or not ns.charKey then return end
    local now = GetTime()
    local elapsed = lastTick and math.min(now - lastTick, 60) or 0
    lastTick = now
    if elapsed <= 0 then return end
    -- both can come back "secret" in combat (not readable): then they count as no, which in combat they are
    if UnitIsAFK and ns.IsTrue(UnitIsAFK("player")) then return end
    if UnitOnTaxi and ns.IsTrue(UnitOnTaxi("player")) then return end
    local z, d = zoneRecord()
    z.t = z.t + elapsed
    d.t = d.t + elapsed
end)

-- ---------------------------------------------------------------- what each zone gives you

ns.Listen("LOOT", function(itemID, count)
    local z, d = zoneRecord()
    add(z.items, itemID, count)
    add(d.items, itemID, count)
end)

ns.Listen("MONEY", function(cat, amount)
    if amount <= 0 then return end
    if cat == "Looted coin" then
        local z, d = zoneRecord()
        z.coin = z.coin + amount
        d.coin = d.coin + amount
    elseif cat == "Quests" then
        local z = zoneRecord()
        z.quest = (z.quest or 0) + amount
    end
end)

-- kills: counted from "X dies, you gain N experience." WoW Forever's client doesn't let addons read the combat log
-- (even registering for COMBAT_LOG_EVENT_UNFILTERED is forbidden, and the game blocks the addon at login), so kills
-- that give no experience (grey mobs, max level) aren't counted.
local function diesPattern()
    local fmt = COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."
    local p = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "%%d+")
    return "^" .. p
end
local DIES
ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(text)
    DIES = DIES or diesPattern()
    if type(text) ~= "string" or not text:match(DIES) then return end
    local z, d = zoneRecord()
    z.kills = z.kills + 1
    d.kills = d.kills + 1
end)

-- ---------------------------------------------------------------- gathering

local pending -- { kind, at }

local function spellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name then return name end
    end
    if GetSpellInfo then return (GetSpellInfo(spellID)) end
end

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not spellID then return end
    local kind = GATHER_SPELLS[spellName(spellID) or ""]
    if kind then pending = { kind = kind, at = GetTime() } end
end)

local function position()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or not pos then return map end
    local x, y = pos:GetXY()
    return map, x and math.floor(x * 1000 + 0.5) / 10, y and math.floor(y * 1000 + 0.5) / 10
end

local lastSource, lastSourceAt
local function onLoot()
    local kind
    if IsFishingLoot and IsFishingLoot() then
        kind = "fishing"
    elseif pending and GetTime() - pending.at <= GATHER_WINDOW then
        kind = pending.kind
    end
    if not kind then return end
    -- the loot window can report itself twice: count each node or corpse once
    local source = GetLootSourceInfo and GetLootSourceInfo(1)
    if source and source == lastSource and lastSourceAt and GetTime() - lastSourceAt < 30 then return end
    lastSource, lastSourceAt = source, GetTime()
    pending = nil

    local items = {}
    local n = GetNumLootItems and GetNumLootItems() or 0
    for slot = 1, n do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local id = link and ns.ItemIDFromLink(link)
        if id then
            local _, _, quantity = GetLootSlotInfo(slot)
            items[id] = (items[id] or 0) + (tonumber(quantity) or 1)
        end
    end
    if not next(items) then return end

    local z, d = zoneRecord()
    for _, rec in ipairs({ z, d }) do
        local g = rec.gathers[kind]
        if not g then
            g = { n = 0, items = {} }
            rec.gathers[kind] = g
        end
        g.n = g.n + 1
        for id, c in pairs(items) do add(g.items, id, c) end
    end

    local map, x, y = position()
    local log = ns.db.gatherLog
    log[#log + 1] = { t = time(), c = ns.charKey, z = zoneName(), m = map, x = x, y = y, k = kind, i = items }
    if #log > GATHER_LOG_MAX + 200 then
        local keep = {}
        for i = #log - GATHER_LOG_MAX + 1, #log do keep[#keep + 1] = log[i] end
        ns.db.gatherLog = keep
    end
end
ns.On("LOOT_READY", onLoot)
ns.On("LOOT_OPENED", onLoot)

-- ---------------------------------------------------------------- who you are

local function readCharacter()
    if not ns.db or not ns.charKey then return end
    local c = ns.db.chars[ns.charKey]
    if not c then return end
    c.level = UnitLevel("player")
    c.race = select(2, UnitRace("player"))
    c.faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    c.guild = GetGuildInfo and GetGuildInfo("player") or c.guild
    -- every profession, including gathering skills, which never open a recipe window
    if GetProfessions and GetProfessionInfo then
        c.profSkill = c.profSkill or {}
        for _, index in ipairs({ GetProfessions() }) do
            if index then
                local ok, name, _, level, maxLevel = pcall(GetProfessionInfo, index)
                if ok and name then
                    c.profSkill[name] = c.profSkill[name] or {}
                    c.profSkill[name].level = level
                    c.profSkill[name].max = maxLevel
                    c.profSkill[name].at = time()
                end
            end
        end
    end
end

ns.OnLoad(function()
    ns.db.zones = ns.db.zones or {}
    ns.db.gatherLog = ns.db.gatherLog or {}
end)
ns.OnLogin(function()
    trimDays()
    C_Timer.After(3, readCharacter) -- profession data isn't ready the moment you log in
end)
ns.On("SKILL_LINES_CHANGED", function() ns.Debounce("readCharacter", 2, readCharacter) end)
ns.On("PLAYER_LEVEL_UP", function() ns.Debounce("readCharacter", 2, readCharacter) end)
ns.On("PLAYER_GUILD_UPDATE", function() ns.Debounce("readCharacter", 2, readCharacter) end)
