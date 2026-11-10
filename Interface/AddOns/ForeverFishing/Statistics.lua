-- Forever Fishing
-- Copyright © 2026 Hamish336. All Rights Reserved.
-- Applies to original Forever Fishing code and assets only.
-- Blizzard-owned assets and trademarks remain property of Blizzard Entertainment.
-- Unauthorized redistribution or modification is prohibited.
local FF = _G.ForeverFishing
local SCHEMA = 2
local LOOT_GRACE = 1.5

local function Number(value)
    value = tonumber(value)
    return value and value == value and value < math.huge and math.max(0, value) or 0
end
local function Count(value) return math.floor(Number(value)) end
local CATCH_MILESTONES = { 10, 50, 100, 250, 500, 1000 }

function FF:GetCatchProgression(count)
    count = Count(count)
    local tier, reached, nextMilestone = 0, 0
    for index, milestone in ipairs(CATCH_MILESTONES) do
        if count >= milestone then tier, reached = index, milestone
        else nextMilestone = milestone; break end
    end
    return { count = count, tier = tier, tiers = #CATCH_MILESTONES, reached = reached,
        nextMilestone = nextMilestone, remaining = nextMilestone and nextMilestone - count or 0,
        fraction = nextMilestone and (count - reached) / (nextMilestone - reached) or 1 }
end
local function Stamp()
    local value = GetServerTime and GetServerTime() or (time and time())
    return value and value > 0 and value or nil
end
local function Owner() return UnitGUID and UnitGUID("player") or "player" end

function FF:NewFishingSession()
    return { casts = 0, catches = 0, successfulCasts = 0, elapsedTotal = 0,
        timedCatches = 0, activeSeconds = 0, records = {} }
end

function FF:CurrentSessionSeconds()
    local session = self.session
    if not session then return 0 end
    return (session.activeSeconds or 0) + (session.activeStarted and math.max(0, GetTime() - session.activeStarted) or 0)
end

local function PauseSessionTime(session)
    if not session or not session.activeStarted then return false end
    session.activeSeconds = (session.activeSeconds or 0) + math.max(0, GetTime() - session.activeStarted)
    session.activeStarted = nil
    return true
end

function FF:SyncSessionRodTime()
    local session = self.session
    if not session or not session.started or not self.FishingRodEquippedNow then return end
    local equipped = self:FishingRodEquippedNow()
    local itemID = GetInventoryItemID and GetInventoryItemID("player", 16)
    if equipped == nil then
        -- Uncached item data is inconclusive, but a changed main hand proves
        -- that the previously confirmed rod is no longer equipped.
        if not (session.activeRodID and itemID and itemID ~= session.activeRodID) then return end
        equipped = false
    end
    local changed
    if equipped then
        session.activeRodID = itemID
        if not session.activeStarted then
            session.activeStarted = GetTime()
            changed = true
        end
    else
        changed = PauseSessionTime(session)
        session.activeRodID = nil
    end
    if changed then self:InvalidateFishingStats() end
end

local function CopySessionRecords(records)
    local copy = {}
    for id, record in pairs(records or {}) do
        local locations = {}
        for place, count in pairs(record.locations or {}) do locations[place] = Count(count) end
        copy[id] = { count = Count(record.count), locations = locations }
    end
    return copy
end

function FF:SessionHasConfirmedCatches(session)
    return type(session) == "table" and Count(session.catches) > 0
end

local function UpdateHistoryEntry(session)
    local entry = session.historyEntry or session.pendingHistoryEntry
    if not entry or not FF:SessionHasConfirmedCatches(session) then return end
    entry.casts = Count(session.casts)
    entry.successfulCasts = Count(session.successfulCasts)
    entry.catches = Count(session.catches)
    entry.elapsedTotal = Number(session.elapsedTotal)
    entry.timedCatches = Count(session.timedCatches)
    entry.records = CopySessionRecords(session.records)
    if not session.historyEntry then
        -- End can precede qualified loot. Keep only a transient ended-session
        -- draft until its own cast confirms a catch; never persist an empty row.
        local history = FF.db.sessionHistory
        if type(history) ~= "table" then history = {}; FF.db.sessionHistory = history end
        local character = history[entry.owner]
        if type(character) ~= "table" then character = {}; history[entry.owner] = character end
        character[#character + 1] = entry
        session.historyEntry, session.pendingHistoryEntry = entry, nil
    end
    FF.sessionHistoryRevision = (FF.sessionHistoryRevision or 0) + 1
end

function FF:FinishHistoricalSession(reason)
    local session = self.session
    if not session or session.casts == 0 or session.historyEntry or session.pendingHistoryEntry then return false end
    local owner = session.owner or (UnitGUID and UnitGUID("player"))
    if type(owner) ~= "string" or owner == "" then return false end
    PauseSessionTime(session)
    local entry = { owner = owner, character = session.character, realm = session.realm,
        startedAt = session.startedAt, endedAt = Stamp(), endedBy = reason,
        activeSeconds = Number(session.activeSeconds) }
    session.pendingHistoryEntry = entry
    UpdateHistoryEntry(session)
    return session.historyEntry ~= nil
end

function FF:EndSession()
    if self.statsCast and not self.statsCast.ended then
        self:Print(FF:LocalizedText("session.end.finish-cast"))
        return
    end
    local saved = self:FinishHistoricalSession("manual")
    if not saved and self:SessionHasConfirmedCatches(self.session) and self.session.casts > 0 then
        self:Print(FF:LocalizedText("session.end.no-character"))
        return
    end
    self:ResetSession()
    self:Print(saved and FF:LocalizedText("session.end.saved") or FF:LocalizedText("session.end.empty"))
end
function FF:InvalidateFishingStats(catches)
    self.statsRevision = (self.statsRevision or 0) + 1
    if catches then self.catchRevision = (self.catchRevision or 0) + 1 end
    if self.RefreshSessionGoals then self:RefreshSessionGoals() end
end
function FF:GetFishingLocation()
    local zone = GetRealZoneText and GetRealZoneText() or (GetZoneText and GetZoneText())
    local sub = GetSubZoneText and GetSubZoneText()
    if zone and zone ~= "" then
        return sub and sub ~= "" and sub ~= zone and (zone .. ": " .. sub) or zone
    end
    return sub and sub ~= "" and sub or nil
end

function FF:InitializeLifetimeStats()
    local db = self.db
    db.journal = type(db.journal) == "table" and db.journal or {}
    local life = type(db.lifetime) == "table" and db.lifetime or {}
    local migrating = life.schema ~= SCHEMA
    local locations, total, unique = {}, 0, 0
    self.pendingCatchNames = {}
    self.requestedCatchValueItems = {}
    for id, entry in pairs(db.journal) do
        if type(entry) == "table" then
            entry.count = Count(entry.count)
            if type(entry.name) ~= "string" or entry.name == "" or entry.name == "Item " .. tostring(id) then
                entry.name = GetItemInfo and GetItemInfo(id) or nil
                if not entry.name then self.pendingCatchNames[id] = true end
            end
            entry.locations = type(entry.locations) == "table" and entry.locations or {}
            if migrating then
                -- Only migrate explicit counts; a last-seen zone cannot place older catches.
                for place, count in pairs(type(entry.zones) == "table" and entry.zones or {}) do
                    if type(place) == "string" and place ~= "" and not entry.locations[place] then
                        entry.locations[place] = { count = Count(count) }
                    end
                end
                entry.zones = nil
            end
            entry.best = entry.best and Count(entry.best) or nil
            entry.first = Number(entry.first) > 0 and Number(entry.first) or nil
            entry.last = Number(entry.last) > 0 and Number(entry.last) or nil
            for place, record in pairs(entry.locations) do
                if type(place) == "string" and type(record) == "table" then
                    record.count = Count(record.count)
                    record.best = record.best and Count(record.best) or nil
                    record.first = Number(record.first) > 0 and Number(record.first) or nil
                    record.last = Number(record.last) > 0 and Number(record.last) or nil
                    if record.count > 0 then locations[place] = (locations[place] or 0) + record.count end
                else entry.locations[place] = nil end
            end
            total = total + entry.count
            if entry.count > 0 then unique = unique + 1 end
        else db.journal[id] = nil end
    end
    if migrating then
        life.legacy = { catchEvents = Count(life.catches), recordedItems = Count(life.items) }
        life.catchCount = math.max(Count(life.catchCount), Count(life.items), total)
        life.verifiedCasts, life.successfulCasts, life.rateCatches, life.rateSeconds = 0, 0, 0, 0
        life.statsSince = Stamp()
        life.detailHistoryPartial = total > 0
        life.schema = SCHEMA
    end
    life.catchCount = math.max(Count(life.catchCount), total)
    for _, key in ipairs({ "casts", "sessions", "verifiedCasts", "successfulCasts", "rateCatches", "timedCatches" }) do life[key] = Count(life[key]) end
    for _, key in ipairs({ "fishingSeconds", "rateSeconds", "elapsedTotal" }) do life[key] = Number(life[key]) end
    life.catches, life.items = nil, nil
    db.lifetime, db.fishingLocations = life, locations
    if type(db.sessionHistory) ~= "table" then db.sessionHistory = {} end
    self.journalCount, self.journalUnique = total, unique
    self.journalLocations = 0
    for _ in pairs(locations) do self.journalLocations = self.journalLocations + 1 end
    self.session = self:NewFishingSession()
    db.cameraAssistOnboardingFailures = math.min(2, Count(db.cameraAssistOnboardingFailures))
    local pending = db.pendingFishingCast
    if type(pending) == "table" and pending.owner == Owner() and pending.ended then
        if not self:ScheduleCameraAssistOnboardingFailure(pending) then
            self:FinalizeCameraAssistOnboardingFailure(pending)
        end
    end
    self:InvalidateFishingStats(true)
end

function FF:FinalizeCameraAssistOnboardingFailure(cast)
    if not cast or not cast.ended or cast.owner ~= Owner() or cast.onboardingFailureResolved then return end
    local saved = self.db.pendingFishingCast
    -- A resumed active cast is still in progress, not an unsuccessful attempt.
    if saved and saved.token == cast.token and not saved.ended then return end
    cast.onboardingFailureResolved = true
    if (cast.cameraAssistAttempt or cast.cameraAssisted) and not cast.success
        and not self.db.cameraAssistOnboardingComplete and Count(self.db.cameraAssistOnboardingFailures) < 2 then
        self.db.cameraAssistOnboardingFailures = math.min(2, Count(self.db.cameraAssistOnboardingFailures) + 1)
        if self.UpdateCameraMarkerInfo and not (InCombatLockdown and InCombatLockdown()) then
            self:UpdateCameraMarkerInfo()
        end
    end
    if saved and saved.token == cast.token and saved.ended then self.db.pendingFishingCast = nil end
end

function FF:ScheduleCameraAssistOnboardingFailure(cast)
    if not cast or not cast.ended or cast.owner ~= Owner() or cast.success or cast.onboardingFailureResolved
        or not (cast.cameraAssistAttempt or cast.cameraAssisted)
        or self.db.cameraAssistOnboardingComplete or Count(self.db.cameraAssistOnboardingFailures) >= 2 then return false end
    if not (C_Timer and C_Timer.After) then return false end
    local db = self.db
    -- Reuse the loot grace window. Never treat STOP-before-LOOT as a failure.
    local elapsed = math.max(0, GetTime() - cast.ended)
    C_Timer.After(math.max(0, LOOT_GRACE - elapsed), function()
        if self.db == db then self:FinalizeCameraAssistOnboardingFailure(cast) end
    end)
    return true
end

function FF:BeginFishingStatistics(resumed)
    local now = GetTime()
    local started = self.castStart or now
    local token = string.format("%s/%.0f", Owner(), started * 1000)
    local previous = self.statsCast
    if previous and previous.token == token then return end
    -- A new cast replaces the old loot owner, settling its remaining outcome.
    self:FinalizeCameraAssistOnboardingFailure(previous)
    local saved = self.db.pendingFishingCast
    local continued = resumed and type(saved) == "table" and saved.token == token and saved.owner == Owner()
    local cast = continued and saved or { token = token, owner = Owner(), started = started,
        location = self:GetFishingLocation(), verified = not resumed, slots = {} }
    cast.slots = type(cast.slots) == "table" and cast.slots or {}
    cast.session = self.session
    cast.ended, cast.reason = nil, nil
    self.statsCast = cast
    -- Save only the small cast record, never its per-login session table.
    self.db.pendingFishingCast = { token = cast.token, owner = cast.owner, started = cast.started,
        location = cast.location, verified = cast.verified, success = cast.success, closed = cast.closed,
        cameraAssisted = cast.cameraAssisted, cameraAssistAttempt = cast.cameraAssistAttempt, slots = cast.slots }
    if not self.session.started then
        self.session.started = now
        self.session.startedAt = Stamp()
        self.session.owner = UnitGUID and UnitGUID("player")
        self.session.character = UnitName and UnitName("player")
        self.session.realm = GetRealmName and GetRealmName()
        self.db.lifetime.sessions = self.db.lifetime.sessions + 1
    end
    if not self.session.activeStarted then self.session.activeStarted = now end
    self.session.activeRodID = GetInventoryItemID and GetInventoryItemID("player", 16)
    self.session.casts = self.session.casts + 1
    if not resumed then
        self.db.lifetime.casts = self.db.lifetime.casts + 1
        self.db.lifetime.verifiedCasts = self.db.lifetime.verifiedCasts + 1
    end
    self.lifetimeCastStartedAt = now
    self:InvalidateFishingStats()
end
function FF:AccrueLifetimeFishingTime()
    if not self.lifetimeCastStartedAt then return end
    local seconds = math.max(0, GetTime() - self.lifetimeCastStartedAt)
    local life = self.db.lifetime
    life.fishingSeconds = life.fishingSeconds + seconds
    if self.statsCast and self.statsCast.verified then life.rateSeconds = life.rateSeconds + seconds end
    self.lifetimeCastStartedAt = nil
    self:InvalidateFishingStats()
end
function FF:EndFishingStatistics(reason)
    self:AccrueLifetimeFishingTime()
    if self.statsCast then self.statsCast.ended, self.statsCast.reason = GetTime(), reason end
    -- Retain only an unresolved assisted outcome through the loot grace window,
    -- including a reload during it. The normal in-memory loot owner is unchanged.
    local cast, saved = self.statsCast, self.db.pendingFishingCast
    if self:ScheduleCameraAssistOnboardingFailure(cast) and saved and saved.token == cast.token then
        saved.ended, saved.reason = cast.ended, cast.reason
    else
        self.db.pendingFishingCast = nil
    end
end
function FF:CloseFishingLoot()
    if self.statsCast and self.statsCast.success then self.statsCast.closed = true end
    if self.db.pendingFishingCast and self.statsCast and self.statsCast.success then self.db.pendingFishingCast.closed = true end
end

local function FishingSource(slot)
    if not GetLootSourceInfo then return nil end
    local result = { pcall(GetLootSourceInfo, slot) }
    if not result[1] then return nil end
    local other, object = false, false
    for i = 2, #result, 2 do
        local guid = result[i]
        if type(guid) == "string" and guid ~= "" then
            if guid:match("^GameObject%-") then object = true else other = true end
            if guid:match("^GameObject%-") and tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) == 35591 then return true end
        end
    end
    if other then return false end
    if object then return "object" end -- Other objects require the native fishing flag.
    return nil
end
local function AddRecord(record, amount, stamp, sessionCount)
    if record.count == 0 then record.first = stamp end
    record.count = record.count + amount
    record.last = stamp
    record.best = math.max(record.best or 0, sessionCount)
end

function FF:RecordLoot()
    local cast = self.statsCast
    if not cast or cast.closed or not GetNumLootItems or not GetLootSlotLink or not GetLootSlotInfo then return end
    local now = GetTime()
    local native
    if IsFishingLoot then
        local ok, value = pcall(IsFishingLoot)
        if ok then native = value end
    end
    local fallback = native == nil and cast.ended and cast.reason == "UNIT_SPELLCAST_CHANNEL_STOP" and now - cast.ended <= LOOT_GRACE
    local totals = {}
    local updates, count, metadataChanged = {}, 0, false
    for slot = 1, GetNumLootItems() do
        local source = FishingSource(slot)
        if source ~= false and (native or source == true or (fallback and source == nil)) then
            local link = GetLootSlotLink(slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then
                local icon, name, quantity = GetLootSlotInfo(slot)
                name = name or (GetItemInfo and GetItemInfo(id))
                local entry = self.db.journal[id]
                if entry and name and entry.name ~= name then entry.name = name; metadataChanged = true end
                if name then self.pendingCatchNames[id] = nil end
                quantity = Count(quantity)
                if quantity > 0 then
                    local item = totals[id]
                    if not item then item = { id = id, name = name, quantity = 0 }; totals[id] = item end
                    item.icon = icon or item.icon
                    item.quantity = item.quantity + quantity
                end
            end
        end
    end
    -- Slot indices can shift during automatic looting. Compare quantities by item,
    -- not by slot, so READY and OPENED cannot count the same catch twice.
    for id, item in pairs(totals) do
        local previous = cast.slots[id] or 0
        if item.quantity > previous then
            item.amount = item.quantity - previous
            updates[#updates + 1] = item
            cast.slots[id] = item.quantity
            count = count + item.amount
        end
    end
    if count == 0 then
        if metadataChanged then self:InvalidateFishingStats(true); self:RefreshUI() end
        return
    end
    local life, session, stamp = self.db.lifetime, cast.session, Stamp()
    local firstCatch = not cast.success
    if firstCatch then
        cast.success = true
        -- A resumed already-recorded cast cannot earn another success after reload.
        session.successfulCasts = session.successfulCasts + 1
        if cast.verified then life.successfulCasts = life.successfulCasts + 1 end
        local elapsed = math.max(0, now - cast.started)
        session.elapsedTotal, session.timedCatches = session.elapsedTotal + elapsed, session.timedCatches + 1
        life.elapsedTotal, life.timedCatches = life.elapsedTotal + elapsed, life.timedCatches + 1
    end
    for _, update in ipairs(updates) do
        local id, amount = update.id, update.amount
        local entry = self.db.journal[id]
        if not entry then entry = { count = 0, locations = {} }; self.db.journal[id] = entry end
        if entry.count == 0 then self.journalUnique = self.journalUnique + 1 end
        local perSession = session.records[id]
        if not perSession then perSession = { count = 0, locations = {} }; session.records[id] = perSession end
        perSession.count = perSession.count + amount
        AddRecord(entry, amount, stamp, perSession.count)
        entry.name = update.name or entry.name
        if not entry.name then
            self.pendingCatchNames[id] = true
        end
        local place = cast.location
        if place then
            local location = entry.locations[place]
            if not location then location = { count = 0 }; entry.locations[place] = location end
            perSession.locations[place] = (perSession.locations[place] or 0) + amount
            AddRecord(location, amount, stamp, perSession.locations[place])
            if not self.db.fishingLocations[place] then self.db.fishingLocations[place] = 0; self.journalLocations = self.journalLocations + 1 end
            self.db.fishingLocations[place] = self.db.fishingLocations[place] + amount
            entry.zone = place
        end
    end
    self.journalCount, life.catchCount = self.journalCount + count, life.catchCount + count
    session.catches = session.catches + count
    UpdateHistoryEntry(session)
    if cast.verified then life.rateCatches = life.rateCatches + count end
    local saved = self.db.pendingFishingCast
    if saved and saved.token == cast.token then
        saved.success = true
        if saved.ended then self.db.pendingFishingCast = nil end
    end
    self.lootRecorded = true
    if cast.cameraAssisted and not self.db.cameraAssistOnboardingComplete then
        self.db.cameraAssistOnboardingComplete = true
        if self.UpdateCameraMarkerInfo then self:UpdateCameraMarkerInfo() end
    end
    if firstCatch and self.RecordAchievementFishingCatch then self:RecordAchievementFishingCatch() end
    if firstCatch and self.OnFishingCatchRecorded then self:OnFishingCatchRecorded() end
    if self.ShowCatchRecap then self:ShowCatchRecap(updates, cast) end
    if self.RefreshFishingAchievements then self:RefreshFishingAchievements(true) end
    self:InvalidateFishingStats(true)
    self:TraceTransition("fishing loot recorded: " .. count .. " item(s)")
    self:RefreshUI()
end
function FF:RefreshCatchItemName(id, success)
    if success == false or not self.pendingCatchNames or not self.pendingCatchNames[id] then return end
    local name = GetItemInfo and GetItemInfo(id)
    if not name then return end
    self.pendingCatchNames[id] = nil
    local entry = self.db.journal[id]
    if entry and entry.name ~= name then
        entry.name = name
        self:InvalidateFishingStats(true)
        self:RefreshUI()
    end
end
function FF:ResetSession()
    self.session = self:NewFishingSession()
    self:InvalidateFishingStats()
    self:RefreshUI()
end
function FF:CurrentFishingSeconds(measured)
    local life = self.db.lifetime
    local seconds = measured and life.rateSeconds or life.fishingSeconds
    if self.lifetimeCastStartedAt and (not measured or (self.statsCast and self.statsCast.verified)) then
        seconds = seconds + math.max(0, GetTime() - self.lifetimeCastStartedAt)
    end
    return seconds
end
function FF:GetCatchJournalItems()
    if self.catchList and self.catchListRevision == self.catchRevision then return self.catchList end
    local items = {}
    for id, entry in pairs(self.db.journal) do
        if entry.count > 0 then items[#items + 1] = { id = tonumber(id) or id, entry = entry } end
    end
    table.sort(items, function(a, b)
        if a.entry.count ~= b.entry.count then return a.entry.count > b.entry.count end
        return (a.entry.name or tostring(a.id)) < (b.entry.name or tostring(b.id))
    end)
    self.catchList, self.catchListRevision = items, self.catchRevision
    return items
end
function FF:GetCatchScopes(entry)
    local rows = { { name = "Lifetime", record = entry, total = self.db.lifetime.catchCount } }
    local places = {}
    for place, record in pairs(entry.locations) do
        if record.count > 0 then places[#places + 1] = { name = place, record = record, total = self.db.fishingLocations[place] or 0 } end
    end
    table.sort(places, function(a,b) if a.record.count ~= b.record.count then return a.record.count > b.record.count end return a.name < b.name end)
    for _, row in ipairs(places) do rows[#rows + 1] = row end
    return rows
end

local function AuctionPrice(id)
    local auctionator = _G.Auctionator
    local api = auctionator and auctionator.API and auctionator.API.v1
    if api and type(api.GetAuctionPriceByItemID) == "function" then
        local ok, price = pcall(api.GetAuctionPriceByItemID, "ForeverFishing", id)
        if ok and type(price) == "number" and price > 0 and price < math.huge then return price end
    end
    local tsm = _G.TSM_API
    if tsm and type(tsm.GetCustomPriceValue) == "function" then
        local itemString = "i:" .. id
        if type(tsm.ToItemString) == "function" then
            local converted, result = pcall(tsm.ToItemString, itemString)
            if converted and type(result) == "string" then itemString = result end
        end
        local ok, price = pcall(tsm.GetCustomPriceValue, "dbmarket", itemString)
        if ok and type(price) == "number" and price > 0 and price < math.huge then return price end
    end
end

local function VendorPrice(id)
    local itemInfo = C_Item and C_Item.GetItemInfo
    local price = itemInfo and select(11, itemInfo(id))
    if price == nil and GetItemInfo and GetItemInfo ~= itemInfo then
        price = select(11, GetItemInfo(id))
    end
    if type(price) == "number" and price >= 0 and price < math.huge then return price end
end

function FF:GetCatchValues(lifetime)
    local records = lifetime and self.db.journal or self.session.records
    local auctionator = _G.Auctionator
    local auctionAPI = auctionator and auctionator.API and auctionator.API.v1
    local tsm = _G.TSM_API
    local values = { vendor = 0, auction = 0, auctionFallback = 0,
        vendorMissing = 0, auctionMissing = 0,
        hasAuctionSource = (auctionAPI and type(auctionAPI.GetAuctionPriceByItemID) == "function")
            or (tsm and type(tsm.GetCustomPriceValue) == "function") or false }
    for key, record in pairs(records) do
        local id, count = tonumber(key), Count(record.count)
        if id and count > 0 then
            local sellPrice = VendorPrice(id)
            if sellPrice then
                values.vendor = values.vendor + sellPrice * count
            else
                values.vendorMissing = values.vendorMissing + count
                self.requestedCatchValueItems = self.requestedCatchValueItems or {}
                if not self.requestedCatchValueItems[id] then
                    self.requestedCatchValueItems[id] = true
                    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
                end
            end
            local auction = AuctionPrice(id)
            if auction then
                values.auction = values.auction + auction * count
            else
                values.auctionMissing = values.auctionMissing + count
                local fallback = (sellPrice or 0) * count
                values.auctionFallback = values.auctionFallback + fallback
                values.auction = values.auction + fallback
            end
        end
    end
    return values
end

function FF:RegisterAuctionPriceUpdates()
    if self.auctionPriceUpdatesRegistered then return end
    local auctionator = _G.Auctionator
    local api = auctionator and auctionator.API and auctionator.API.v1
    if not api or type(api.RegisterForDBUpdate) ~= "function" then return end
    local ok = pcall(api.RegisterForDBUpdate, "ForeverFishing", function()
        if not FF.db then return end
        FF:InvalidateFishingStats()
        if FF.RefreshJournal then FF:RefreshJournal() end
    end)
    if ok then self.auctionPriceUpdatesRegistered = true end
end
