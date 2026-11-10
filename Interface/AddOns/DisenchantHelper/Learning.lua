-- Learning.lua (1.8.0-dev)
-- Records what YOUR disenchants actually produce, locally, in SavedVariables.
-- Nothing is sent anywhere. The data feeds the (upcoming) expected-value
-- prediction and is shown with /deh de.
--
-- How a result is attributed (and why it is conservative):
--   1. Begin(item)        - the queue click armed a disenchant: snapshot the item
--                           NOW (the item is destroyed by the cast).
--   2. OnCastSucceeded()  - the client confirms OUR disenchant spell finished.
--   3. OnLootOpened()     - the first loot window right after that success is
--                           the disenchant result; read its slots and count them.
-- No cast confirmation = nothing is recorded, so loot from anywhere else can
-- never leak into the statistics.
--
-- Storage: one counter group per (quality, armor/weapon, item level, required
-- level). Both levels are kept on purpose, so "does the item level or the
-- required level decide the result" can be answered from real data.

local _, ns = ...
ns.L = ns.L or {}
local L = ns.L

local Learn = {}
ns.Learn = Learn

-- Knowledge consumables are progression rewards, not crafting materials.
-- Numeric IDs are language-independent; never infer from the displayed name.
-- https://www.wowhead.com/item=267654/swirling-arcane-essence
-- https://www.wowhead.com/item=267655/brimming-mana-shard
local ignoredMaterials={ [267654]=true, [267655]=true }
function Learn.IsIgnoredMaterial(id) return ignoredMaterials[id]==true end
function Learn.FilterMaterials(got)
    local filtered={}
    for id,qty in pairs(got) do
        if not Learn.IsIgnoredMaterial(id) then filtered[id]=qty end
    end
    return filtered
end

Learn.spellID = 13262            -- Disenchant (overridden by the main file)

local MAX_BUCKETS = 4000         -- hard cap: protects SavedVariables size
local MAX_MATERIALS_PER_BUCKET, MAX_MATERIAL_ENTRIES, MAX_CACHE = 16, 32000, 256
local MAX_INTEGER = 9007199254740991 -- largest exactly representable Lua double integer
Learn.Limits={groups=MAX_BUCKETS,perGroup=MAX_MATERIALS_PER_BUCKET,materials=MAX_MATERIAL_ENTRIES,cache=MAX_CACHE}
local CAST_WINDOW = 12           -- seconds: click -> cast success must be seen
local LOOT_WINDOW = 3            -- seconds: cast success -> loot window opens
local RECENT_LINES = 12          -- default length of /deh de

local root                       -- db.learn (set by Init)
local bucketCount = 0
local pending                    -- snapshot of the disenchant in flight
local session = { casts = 0, recorded = 0 }
local observedCache = {}
local cacheCount, materialCount = 0, 0

local function Integer(value,minimum)
    return type(value)=="number" and value>=minimum and value<=MAX_INTEGER and value==math.floor(value)
end
local function ClearCache() observedCache={};cacheCount=0 end
local function Cache(key,value)
    if observedCache[key]==nil then
        if cacheCount>=MAX_CACHE then ClearCache() end
        cacheCount=cacheCount+1
    end
    observedCache[key]=value
end
local function AtLimit()
    Learn.capacitySkipped=(Learn.capacitySkipped or 0)+1
    if not Learn.limitReached and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("Disenchant Helper: "..L["LEARN_STORAGE_LIMIT"])
    end
    Learn.limitReached=true
    return false
end
function Learn.GetStorageUsage()
    return {groups=bucketCount,materials=materialCount,cache=cacheCount,skipped=Learn.capacitySkipped or 0}
end

local function Now()
    return (GetTime and GetTime()) or 0
end

-- ---------------------------------------------------------------------------
-- Item facts (always through pcall'd, version-tolerant lookups)
-- ---------------------------------------------------------------------------
local function GetClassID(link)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return nil end
    local ok, _, _, _, _, _, classID = pcall(f, link)
    if ok then return tonumber(classID) end
end

local function GetRequiredLevel(link)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    local ok, _, _, _, _, req = pcall(f, link)
    if ok then return tonumber(req) end
end

local function MaterialName(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name
    if f then
        local ok, n = pcall(f, id)
        if ok then name = n end
    end
    return (type(name) == "string" and name) or ("#" .. tostring(id))
end

-- Snapshot of the queued item. nil = not something we can classify (skipped).
local function MakeSnapshot(item)
    if type(item) ~= "table" or not item.link then return nil end
    local quality = tonumber(item.quality)
    local ilvl = tonumber(item.itemLevel)
    if not quality or not ilvl or ilvl <= 0 then return nil end
    local classID = GetClassID(item.link)
    local kind = (classID == 2 and "W") or (classID == 4 and "A") or nil
    if not kind then return nil end
    -- -1 = unknown. 0 is a REAL value (some items need no level).
    return { quality = quality, ilvl = ilvl, kind = kind, req = GetRequiredLevel(item.link) or -1 }
end

Learn.Classify = MakeSnapshot
Learn.MaterialName = MaterialName

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------
local function ValidMaterial(m,n)
    return type(m)=="table" and Integer(m.c,1) and m.c<=n
        and Integer(m.qtySum,1) and Integer(m.minQty,1) and Integer(m.maxQty,m.minQty)
        and m.qtySum/m.c>=m.minQty and m.qtySum/m.c<=m.maxQty
end
local function Validate(data,legacy)
    if type(data)~="table" or type(data.buckets)~="table" or not Integer(data.total,0) or not Integer(data.seq,0) then return false end
    for key,b in pairs(data.buckets) do
        if type(key)~="string" or type(b)~="table" or not Integer(b.q,0)
            or (b.k~="A" and b.k~="W") or not Integer(b.l,1) or not Integer(b.r,-1)
            or not Integer(b.n,0) or not Integer(b.t,0) or type(b.m)~="table" then return false end
        for id,m in pairs(b.m) do
            if not Integer(id,1) or type(m)~="table" then return false end
            if legacy then
                if not Integer(m.c,1) or m.c>b.n or type(m.q)~="table" then return false end
                local occurrences,sum=0,0
                for qty,count in pairs(m.q) do
                    if not Integer(qty,1) or not Integer(count,1) then return false end
                    occurrences=occurrences+count;sum=sum+qty*count
                    if not Integer(occurrences,0) or not Integer(sum,0) then return false end
                end
                if occurrences~=m.c then return false end
            elseif not ValidMaterial(m,b.n) then return false end
        end
    end
    return true
end
local function Migrate(data)
    local result={v=2,total=data.total,seq=data.seq,buckets={}}
    for key,b in pairs(data.buckets) do
        local copy={q=b.q,k=b.k,l=b.l,r=b.r,n=b.n,t=b.t,m={}}
        result.buckets[key]=copy
        for id,m in pairs(b.m) do
            local sum,lo,hi=0,nil,nil
            for qty,count in pairs(m.q) do
                sum=sum+qty*count;lo=lo and math.min(lo,qty) or qty;hi=hi and math.max(hi,qty) or qty
            end
            copy.m[id]={c=m.c,qtySum=sum,minQty=lo,maxQty=hi}
        end
    end
    return result
end
function Learn.Init(dbRoot)
    root, pending, bucketCount = nil, nil, 0
    ClearCache();materialCount=0
    Learn.limitReached=false;Learn.capacitySkipped=0
    Learn.storageBlocked = false
    if type(dbRoot) ~= "table" then return false end
    local learn=dbRoot.learn
    if learn==nil then
        learn={v=2,total=0,seq=0,buckets={}}
        dbRoot.learn=learn
    elseif type(learn)=="table" and learn.v==2 then
        if not Validate(learn,false) then learn=nil end
    elseif type(learn)=="table" and learn.v~=nil and learn.v~=1 then
        learn=nil -- unknown versions are never repaired or migrated
    else
        -- Preserve the existing repair policy and its independent backup.
        -- Migration has its own one-time snapshot and never replaces either.
        if dbRoot.learnMigrationBackup~=nil then
            learn=nil
        else
            learn=ns.SavedData.Prepare(dbRoot,"learn",function(data)
                return type(data.buckets)=="table" and type(data.total)=="number" and type(data.seq)=="number"
            end,function()return {v=1,total=0,seq=0,buckets={}} end)
            if learn then
                if type(learn.buckets)~="table" then learn.buckets={} end
                learn.total=tonumber(learn.total) or 0;learn.seq=tonumber(learn.seq) or 0
                if Validate(learn,true) then
                    local compact=Migrate(learn)
                    dbRoot.learnMigrationBackup=learn -- original object retained, never modified again
                    dbRoot.learn=compact;learn=compact
                else learn=nil end
            end
        end
    end
    if not learn then
        Learn.storageBlocked = true
        return false
    end
    if type(learn.buckets) ~= "table" then learn.buckets = {} end
    learn.total = tonumber(learn.total) or 0
    learn.seq = tonumber(learn.seq) or 0
    root = learn
    bucketCount = 0
    for _,b in pairs(learn.buckets) do
        bucketCount = bucketCount + 1
        for _ in pairs(b.m) do materialCount=materialCount+1 end
    end
    return true
end

local function Commit(snap, got)
    ClearCache()
    local key = string.format("%d:%s:%d:%d", snap.quality, snap.kind, snap.ilvl, snap.req)
    local bucket = root.buckets[key]
    if not bucket then
        if bucketCount >= MAX_BUCKETS then return AtLimit() end
        bucket = { q = snap.quality, k = snap.kind, l = snap.ilvl, r = snap.req, n = 0, t = 0, m = {} }
    end
    -- Preflight the WHOLE observation: partial results would bias probabilities.
    local count,new=0,0
    for _ in pairs(bucket.m) do count=count+1 end
    for id,qty in pairs(got) do
        if not Integer(id,1) or not Integer(qty,1) then return false end
        local m=bucket.m[id]
        if m then
            if not Integer(m.c+1,1) or not Integer(m.qtySum+qty,1) then return AtLimit() end
        else new=new+1 end
    end
    if new>0 and (count+new>MAX_MATERIALS_PER_BUCKET or materialCount+new>MAX_MATERIAL_ENTRIES) then return AtLimit() end
    if not Integer(root.total+1,0) or not Integer(root.seq+1,0) or not Integer(bucket.n+1,0) then return AtLimit() end
    if not root.buckets[key] then root.buckets[key]=bucket;bucketCount=bucketCount+1 end
    materialCount=materialCount+new
    root.seq = root.seq + 1
    root.total = root.total + 1
    bucket.n = bucket.n + 1
    bucket.t = root.seq
    for id, qty in pairs(got) do
        local mat = bucket.m[id]
        if not mat then
            mat = { c = 0, qtySum = 0, minQty = qty, maxQty = qty }
            bucket.m[id] = mat
        end
        mat.c = mat.c + 1
        mat.qtySum=mat.qtySum+qty
        mat.minQty=math.min(mat.minQty,qty);mat.maxQty=math.max(mat.maxQty,qty)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Event entry points (the main file calls these, wrapped in pcall)
-- ---------------------------------------------------------------------------
function Learn.Begin(item, statsOnly)
    pending = nil
    if not root then return end
    -- Explicit Forever materials share cast/loot attribution, not gear buckets.
    if statsOnly then
        pending = { startedAt = Now(), statsOnly = true }
        return
    end
    local snap = MakeSnapshot(item)
    if not snap then return end
    snap.startedAt = Now()
    -- Prediction BEFORE this disenchant is recorded (out-of-sample), and the
    -- item's market value, for the statistics. Both optional, never fatal.
    if ns.Prediction and ns.Prediction.Estimate then
        local ok, est = pcall(ns.Prediction.Estimate, item)
        if ok and type(est) == "table" then
            if (est.n and est.n > 0 or est.priorWeight) and est.missing == 0 then snap.expected = est.ev end
            snap.sellNet = est.sell
        end
    end
    pending = snap
end

-- A bounded recent-ID window deduplicates both helper and manual successes.
local recentIDs, recentSet, recentIndex = {}, {}, 1
local function ReadCastGUID(guid)
    if issecretvalue and issecretvalue(guid) then return nil end
    if type(guid)=="string" and guid~="" then return guid end
end

function Learn.OnCastSent(spellID, guid)
    if pending and not pending.castGUID and not pending.succeededAt
        and spellID==Learn.spellID and Now()-pending.startedAt<=CAST_WINDOW then
        pending.castGUID=ReadCastGUID(guid)
    end
end

function Learn.OnCastFailed(spellID, guid)
    guid=ReadCastGUID(guid)
    if guid and pending and not pending.succeededAt and pending.castGUID==guid and spellID==Learn.spellID then
        pending=nil
    end
end

function Learn.OnCastSucceeded(spellID, guid)
    if not root or spellID ~= Learn.spellID then return end
    guid=ReadCastGUID(guid)
    if guid then
        if recentSet[guid] then return end
        local old=recentIDs[recentIndex]
        if old then recentSet[old]=nil end
        recentIDs[recentIndex]=guid;recentSet[guid]=true
        recentIndex=recentIndex%64+1
    end
    local t = Now()
    if pending and t-pending.startedAt>CAST_WINDOW then pending=nil end
    if not pending or pending.succeededAt or (pending.castGUID and guid and pending.castGUID~=guid) then
        if guid and ns.Stats and ns.Stats.RecordManualCast then
            pending=nil -- do not attribute this cast's loot to a stale helper attempt
            ns.Stats.RecordManualCast()
        end
        return
    end
    pending.succeededAt = t
    if not pending.statsOnly then session.casts = session.casts + 1 end
end

local function ReadLoot()
    local got = {}
    local n = (GetNumLootItems and GetNumLootItems()) or 0
    for i = 1, n do
        local link = GetLootSlotLink and GetLootSlotLink(i)
        if link then
            local id = tonumber(string.match(link, "item:(%d+)"))
            if id and not Learn.IsIgnoredMaterial(id) then
                local qty = 1
                if GetLootSlotInfo then
                    local _, _, q = GetLootSlotInfo(i)
                    qty = math.max(1, tonumber(q) or 1)
                end
                got[id] = (got[id] or 0) + qty
            end
        end
    end
    return got
end

function Learn.OnLootOpened()
    if not (root and pending and pending.succeededAt) then return end
    local snap = pending
    pending = nil                       -- one disenchant = one loot window
    if Now() - snap.succeededAt > LOOT_WINDOW then return end
    local got = ReadLoot()
    if next(got) then
        if not snap.statsOnly and Commit(snap, got) then
            session.recorded = session.recorded + 1
        end
        if ns.Stats and ns.Stats.Record then
            pcall(ns.Stats.Record, snap, got)
        end
    end
end

function Learn.Reset()
    if not root then return false end
    ClearCache();materialCount=0;Learn.limitReached=false;Learn.capacitySkipped=0
    root.buckets = {}
    root.total = 0
    root.seq = 0
    bucketCount = 0
    pending = nil
    return true
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------
-- Aggregates every group with this quality / armor-or-weapon / ITEM level
-- (all required levels together). Returns nil when nothing was recorded.
function Learn.GetObserved(quality, kind, ilvl)
    if not root then return nil end
    local cacheKey = tostring(quality) .. ":" .. tostring(kind) .. ":" .. tostring(ilvl)
    if observedCache[cacheKey] ~= nil then return observedCache[cacheKey] or nil end
    local n, mats = 0, {}
    for _, b in pairs(root.buckets) do
        if b.q == quality and b.k == kind and b.l == ilvl then
            n = n + b.n
            for id, m in pairs(b.m) do
                if not Learn.IsIgnoredMaterial(id) then
                    local agg = mats[id] or { id = id, c = 0, qtySum = 0, minQty = nil, maxQty = nil }
                    mats[id] = agg
                    agg.c = agg.c + m.c
                    agg.qtySum=agg.qtySum+m.qtySum
                    agg.minQty=agg.minQty and math.min(agg.minQty,m.minQty) or m.minQty
                    agg.maxQty=agg.maxQty and math.max(agg.maxQty,m.maxQty) or m.maxQty
                end
            end
        end
    end
    if n == 0 then Cache(cacheKey,false); return nil end
    local list = {}
    for _, agg in pairs(mats) do
        agg.chance = agg.c / n
        agg.avgQty = agg.qtySum / agg.c
        list[#list + 1] = agg
    end
    table.sort(list, function(a, b)
        if a.chance ~= b.chance then return a.chance > b.chance end
        return a.id < b.id
    end)
    local result = { n = n, mats = list }
    Cache(cacheKey,result)
    return result
end

-- ---------------------------------------------------------------------------
-- /deh de report (plain text lines; also used for the copy window)
-- ---------------------------------------------------------------------------
local function QualityName(q)
    -- Keep the quality ID; some clients use different localized rarity names.
    return rawget(L, "QUALITY_" .. tostring(q)) or tostring(q)
end

local function FormatMaterials(bucket)
    local parts = {}
    local ids = {}
    for id in pairs(bucket.m) do
        if not Learn.IsIgnoredMaterial(id) then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local ca, cb = bucket.m[a].c, bucket.m[b].c
        if ca ~= cb then return ca > cb end
        return a < b
    end)
    for _, id in ipairs(ids) do
        local m = bucket.m[id]
        local lo, hi=m.minQty,m.maxQty
        local qtyText = (lo == hi) and ("x" .. lo) or ("x" .. lo .. "-" .. hi)
        parts[#parts + 1] = string.format("%s %s %d/%d", MaterialName(id), qtyText, m.c, bucket.n)
    end
    return table.concat(parts, "; ")
end

function Learn.BuildReport(showAll)
    local lines = {}
    if not root then
        lines[1] = L[Learn.storageBlocked and "STORAGE_BLOCKED" or "LEARN_NOT_READY"]
        return lines
    end
    lines[1] = string.format(L["LEARN_HEADER"], root.total, bucketCount, session.casts, session.recorded)
    if Learn.limitReached then lines[#lines+1]=L["LEARN_STORAGE_LIMIT"] end
    if bucketCount == 0 then
        lines[2] = L["LEARN_EMPTY"]
        return lines
    end

    local list = {}
    for _, b in pairs(root.buckets) do
        list[#list + 1] = b
    end
    if showAll then
        table.sort(list, function(a, b)
            if a.q ~= b.q then return a.q < b.q end
            if a.k ~= b.k then return a.k < b.k end
            if a.l ~= b.l then return a.l < b.l end
            return a.r < b.r
        end)
    else
        table.sort(list, function(a, b) return a.t > b.t end)
        if #list > RECENT_LINES then
            lines[#lines + 1] = string.format(L["LEARN_RECENT"], RECENT_LINES)
            for i = #list, RECENT_LINES + 1, -1 do list[i] = nil end
        end
    end

    for _, b in ipairs(list) do
        lines[#lines + 1] = string.format(L["LEARN_LINE"],
            QualityName(b.q), L["LEARN_KIND_" .. b.k] or b.k, b.l,
            (b.r >= 0) and tostring(b.r) or "?", b.n, FormatMaterials(b))
    end
    return lines
end
