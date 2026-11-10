-- Stats.lua (1.8.0-dev3)
-- Session and all-time statistics of your disenchants.
--
-- Fed by Learning.lua after every recorded disenchant (Record), displayed by
-- the statistics window of the main file (BuildLines -> plain text lines).
--
-- What is measured, and how honestly:
--   * counts and material amounts are exact (read from the loot window).
--   * "value" = market value of the materials AT THE TIME of the disenchant,
--     from TSM/Auctionator. It is an estimate, not earned gold. A disenchant
--     whose materials are not ALL priced is counted but not valued - a missing
--     price is never treated as 0.
--   * "vs selling" compares material value with the market value of the
--     destroyed item, both after the AH cut, and only over disenchants where
--     both prices were known.
--   * "prediction vs reality" compares the expected value computed BEFORE the
--     cast (from earlier data only) with what actually dropped.
-- All-time counts and material totals are backfilled from the learned data;
-- values can only be tracked from the first run of this version on.

local _, ns = ...
ns.L = ns.L or {}
local L = ns.L

local Stats = {}
ns.Stats = Stats
local function Ignored(id)
    return ns.Learn and ns.Learn.IsIgnoredMaterial and ns.Learn.IsIgnoredMaterial(id)
end

local MAX_MATERIAL_LINES = 12
local MAX_MATERIALS, MAX_INTEGER = 512, 9007199254740991
Stats.MAX_MATERIALS=MAX_MATERIALS
local materialCounts=setmetatable({}, {__mode="k"})
local function CountMaterials(t)
    if materialCounts[t]==nil then
        local count=0;for _ in pairs(t.mats) do count=count+1 end
        materialCounts[t]=count
    end
    return materialCounts[t]
end
local function CanAdd(t,got)
    if type(t.de)~="number" or t.de<0 or t.de>=MAX_INTEGER then return false end
    local new=0
    for id,qty in pairs(got) do
        if type(id)~="number" or id<=0 or id>MAX_INTEGER or id~=math.floor(id)
            or type(qty)~="number" or qty<=0 or qty~=math.floor(qty) or qty>MAX_INTEGER then return false end
        if t.mats[id]==nil then new=new+1
        elseif type(t.mats[id])~="number" or t.mats[id]+qty>MAX_INTEGER then return false end
    end
    return new==0 or CountMaterials(t)+new<=MAX_MATERIALS
end

local root          -- db.stats
local session       -- { startedAt, totals }

local function Now()
    return (time and time()) or 0
end

local function NewTotals()
    return {
        de = 0,            -- disenchants recorded
        mats = {},         -- itemID -> total quantity
        valued = 0,        -- disenchants whose materials were all priced
        matValue = 0,      -- copper, summed over the valued disenchants
        expN = 0,          -- disenchants with a prediction AND a value
        expSum = 0,        -- copper: expected value over those
        expActual = 0,     -- copper: actual value over those
        netN = 0,          -- disenchants with material AND item price
        net = 0,           -- copper: (materials - item) * (1 - AH cut)
    }
end

local NUMERIC_FIELDS = { "de", "valued", "matValue", "expN", "expSum", "expActual", "netN", "net" }

local function RepairTotals(t)
    if type(t) ~= "table" then t = NewTotals() end
    for _, key in ipairs(NUMERIC_FIELDS) do
        if type(t[key]) ~= "number" then t[key] = 0 end
    end
    if type(t.mats) ~= "table" then t.mats = {} end
    return t
end

-- ---------------------------------------------------------------------------
-- Init / reset
-- ---------------------------------------------------------------------------
function Stats.Init(dbRoot)
    root, session = nil, nil
    Stats.limitReached=false;Stats.capacitySkipped=0
    materialCounts=setmetatable({}, {__mode="k"})
    Stats.storageBlocked = false
    if type(dbRoot) ~= "table" then return false end
    -- Do not backfill or modify statistics from an unreadable learning schema.
    if ns.Learn and ns.Learn.storageBlocked then
        Stats.storageBlocked = true
        return false
    end
    local needsBackfill = dbRoot.stats == nil or type(dbRoot.stats) ~= "table"
        or type(dbRoot.stats.all) ~= "table"
    local s = ns.SavedData.Prepare(dbRoot, "stats", function(data)
        if type(data.all) ~= "table" or type(data.all.mats) ~= "table"
            or type(data.valueSince) ~= "number" then return false end
        for _, key in ipairs(NUMERIC_FIELDS) do
            if type(data.all[key]) ~= "number" then return false end
        end
        return true
    end, function() return { v = 1, valueSince = Now(), all = NewTotals() } end)
    if not s then
        Stats.storageBlocked = true
        return false
    end
    if needsBackfill then
        s.all = NewTotals()
        -- Backfill counts and material amounts from the learned data.
        local learn = dbRoot.learn
        if type(learn) == "table" and type(learn.buckets) == "table" then
            for _, b in pairs(learn.buckets) do
                if type(b) == "table" and type(b.m) == "table" then
                    s.all.de = s.all.de + (tonumber(b.n) or 0)
                    for id, m in pairs(b.m) do
                        if not Ignored(id) then
                            if type(m)=="table" and type(m.qtySum)=="number" then
                                s.all.mats[id]=(s.all.mats[id] or 0)+m.qtySum
                            elseif type(m) == "table" and type(m.q) == "table" then
                                for qty, cnt in pairs(m.q) do
                                    s.all.mats[id] = (s.all.mats[id] or 0) + qty * cnt
                                end
                            end
                        end
                    end
                end
            end
        end
        dbRoot.stats = s
    end
    s.all = RepairTotals(s.all)
    if type(s.valueSince) ~= "number" then s.valueSince = Now() end
    root = s
    session = { startedAt = Now(), totals = NewTotals() }
    return true
end

function Stats.ResetSession()
    if not root then return false end
    session = { startedAt = Now(), totals = NewTotals() }
    if Stats.onChange then pcall(Stats.onChange) end
    return true
end
function Stats.GetStorageUsage()
    return {all=root and CountMaterials(root.all) or 0,
        session=session and CountMaterials(session.totals) or 0,skipped=Stats.capacitySkipped or 0}
end

-- Clears the all-time numbers only; the learned disenchant data is untouched.
function Stats.ResetAll()
    if not root then return false end
    root.all = NewTotals()
    root.valueSince = Now()
    if Stats.onChange then pcall(Stats.onChange) end
    return true
end

-- ---------------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------------
local function AddTo(t, got, matValue, allPriced, snap)
    t.de = t.de + 1
    for id, qty in pairs(got) do
        if t.mats[id]==nil then materialCounts[t]=CountMaterials(t)+1 end
        t.mats[id] = (t.mats[id] or 0) + qty
    end
    if not allPriced then return end
    t.valued = t.valued + 1
    t.matValue = t.matValue + matValue
    if snap.expected then
        t.expN = t.expN + 1
        t.expSum = t.expSum + snap.expected
        t.expActual = t.expActual + matValue
    end
    if snap.sellNet then
        local cut = (ns.Prediction and ns.Prediction.AH_CUT) or 0.05
        t.netN = t.netN + 1
        t.net = t.net + (matValue * (1 - cut) - snap.sellNet)
    end
end

-- snap: item snapshot from Learning (may carry .expected / .sellNet, copper)
-- got:  { itemID = quantity } from the loot window
local function ManualCount(t)
    local n=t.manual
    return type(n)=="number" and n>=0 and n<=MAX_INTEGER and n==math.floor(n) and n or 0
end

function Stats.RecordManualCast()
    if not root or not session then return end
    local current, all = ManualCount(session.totals), ManualCount(root.all)
    if current>=MAX_INTEGER or all>=MAX_INTEGER then return end
    session.totals.manual=current+1
    root.all.manual=all+1
    if Stats.onChange then pcall(Stats.onChange) end
end

function Stats.Record(snap, got)
    if not (root and session and type(got) == "table" and next(got)) then return end
    if ns.Learn and ns.Learn.FilterMaterials then got=ns.Learn.FilterMaterials(got) end
    if not next(got) then return false end
    -- Reject a whole result if either view is full; never count a partial drop
    -- as complete or silently prune existing material totals.
    if not CanAdd(root.all,got) or not CanAdd(session.totals,got) then
        Stats.capacitySkipped=(Stats.capacitySkipped or 0)+1
        if not Stats.limitReached and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("Disenchant Helper: "..L["STATS_STORAGE_LIMIT"])
        end
        Stats.limitReached=true
        return false
    end
    snap = snap or {}
    local matValue, allPriced = 0, true
    for id, qty in pairs(got) do
        local price = ns.Prediction and ns.Prediction.MaterialPrice and ns.Prediction.MaterialPrice(id)
        if type(price) == "number" then
            matValue = matValue + price * qty
        else
            allPriced = false
        end
    end
    AddTo(session.totals, got, matValue, allPriced, snap)
    AddTo(root.all, got, matValue, allPriced, snap)
    if Stats.onChange then pcall(Stats.onChange) end
end

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------
local function Money(copper)
    if ns.Prediction and ns.Prediction.Money then return ns.Prediction.Money(copper) end
    return tostring(math.floor((copper or 0) + 0.5)) .. " c"
end

local function Duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
end

local function DateText(t)
    return (date and date("%Y-%m-%d", t)) or tostring(t)
end

local function MaterialLines(mats, lines)
    local ids = {}
    for id in pairs(mats) do ids[#ids + 1] = id end
    for i=#ids,1,-1 do if Ignored(ids[i]) then table.remove(ids,i) end end
    if #ids == 0 then
        lines[#lines + 1] = L["STATS_MATS_NONE"]
        return
    end
    table.sort(ids, function(a, b)
        if mats[a] ~= mats[b] then return mats[a] > mats[b] end
        return a < b
    end)
    lines[#lines + 1] = L["STATS_MATS"]
    for i = 1, math.min(MAX_MATERIAL_LINES, #ids) do
        local name = (ns.Learn and ns.Learn.MaterialName and ns.Learn.MaterialName(ids[i])) or ("#" .. ids[i])
        if ns.Prediction and ns.Prediction.MaterialIcon then
            name=ns.Prediction.MaterialIcon(ids[i]).." "..name
        end
        lines[#lines + 1] = string.format(L["STATS_MAT_LINE"], name, mats[ids[i]])
    end
    if #ids > MAX_MATERIAL_LINES then
        lines[#lines + 1] = string.format(L["STATS_MATS_MORE"], #ids - MAX_MATERIAL_LINES)
    end
end

-- view = "session" | "all"; returns a list of plain text lines.
function Stats.BuildLines(view)
    local lines = {}
    if not (root and session) then
        lines[1] = L[Stats.storageBlocked and "STORAGE_BLOCKED" or "STATS_NOT_READY"]
        return lines
    end
    if Stats.limitReached then lines[#lines+1]=L["STATS_STORAGE_LIMIT"] end
    local isSession = (view ~= "all")
    local t = isSession and session.totals or root.all
    local cutPct = math.floor(((ns.Prediction and ns.Prediction.AH_CUT) or 0.05) * 100 + 0.5)

    if isSession then
        lines[#lines + 1] = string.format(L["STATS_HEAD_SESSION"],
            Duration(Now() - session.startedAt))
    else
        lines[#lines + 1] = string.format(L["STATS_HEAD_ALL"], DateText(root.valueSince))
    end
    -- Historical financial aggregates lack per-cast prices: do not fabricate a
    -- retrospective correction or reset unrelated user statistics.
    for id in pairs(t.mats) do
        if Ignored(id) then lines[#lines+1]=L["STATS_KNOWLEDGE_HISTORY"];break end
    end
    lines[#lines + 1] = " "

    if t.valued < t.de then
        lines[#lines + 1] = string.format(L["STATS_COUNT_VALUED"], t.de, t.valued)
    else
        lines[#lines + 1] = string.format(L["STATS_COUNT"], t.de)
    end
    lines[#lines + 1] = string.format(L["STATS_MANUAL_COUNT"], ManualCount(t))

    if t.valued > 0 then
        lines[#lines + 1] = string.format(L["STATS_VALUE"], Money(t.matValue))
        lines[#lines + 1] = string.format(L["STATS_VALUE_AVG"], Money(t.matValue / t.valued))
    else
        lines[#lines + 1] = L["STATS_NO_VALUE"]
    end

    if isSession and t.valued > 0 then
        local hours = (Now() - session.startedAt) / 3600
        if hours >= (1 / 60) then
            lines[#lines + 1] = string.format(L["STATS_PER_HOUR"], t.de / hours, Money(t.matValue / hours))
        end
    end

    if t.netN > 0 then
        if t.net >= 0 then
            lines[#lines + 1] = string.format(L["STATS_NET_GOOD"], cutPct, Money(t.net), t.netN)
        else
            lines[#lines + 1] = string.format(L["STATS_NET_BAD"], cutPct, Money(-t.net), t.netN)
        end
    else
        lines[#lines + 1] = L["STATS_NET_NONE"]
    end

    if t.expN > 0 then
        local ratio = (t.expSum > 0) and math.floor(t.expActual / t.expSum * 100 + 0.5) or 0
        lines[#lines + 1] = string.format(L["STATS_PRED"], Money(t.expSum), Money(t.expActual), t.expN, ratio)
    else
        lines[#lines + 1] = L["STATS_PRED_NONE"]
    end

    lines[#lines + 1] = " "
    MaterialLines(t.mats, lines)
    return lines
end
