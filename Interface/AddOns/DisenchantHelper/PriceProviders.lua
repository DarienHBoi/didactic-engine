-- ---------------------------------------------------------------------------
-- Price provider layer (v1.5.0 value guard)
--
-- Design (see BACKLOG "Preisprovider + Compact Mode"): the warning logic and
-- the UI never talk to TSM or Auctionator directly. They only ever see a
-- normalized result - a copper value plus a source label - from this module.
-- Why: price addons come and go, their APIs throw errors on bad input, and
-- users may have neither installed. All of that risk is contained HERE, so a
-- broken or missing price addon can never break Disenchant Helper itself.
-- If no provider yields a usable value, callers get nil and the addon behaves
-- exactly as it does today.
-- ---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

ns.Prices = ns.Prices or {}
local Prices = ns.Prices

-- Auctionator's API contract requires a caller ID string ("use the name of
-- your add-on") so THEIR error messages can point users at the right addon.
local CALLER_ID = ADDON_NAME or "DisenchantHelper"

-- Short-lived cache: bag refreshes hit the same items many times in a row,
-- but market data only changes on a TSM app sync or a new Auctionator scan -
-- so re-asking every provider on every refresh would be pure waste.
-- 60s is short enough that a fresh AH scan shows up "soon enough".
local CACHE_TTL = 60
local cache = {}
local MAX_CACHE, cacheCount = 256, 0
local function CacheResult(key,value)
    if cache[key]==nil then
        if cacheCount>=MAX_CACHE then cache={};cacheCount=0 end
        cacheCount=cacheCount+1
    end
    cache[key]=value
end
function Prices.GetCacheUsage() return cacheCount,MAX_CACHE end

-- ---------------------------------------------------------------------------
-- Providers, in priority order. Each provider is a small table:
--   key    - stable identifier (settings, /deh check)
--   label  - short human-readable source name for the UI ("TSM", "Auctionator")
--   IsAvailable() - cheap presence check, safe to call every time (feature
--                   detection, same pattern as our Retail/Classic API guards)
--   GetCopper(itemLink) - normalized price in copper, or nil if unknown.
--                   May assume IsAvailable() returned true.
--
-- Both external APIs can raise real Lua errors (Auctionator's error() calls
-- are part of its documented contract; TSM throws on malformed input), so
-- every external call below runs through pcall: *their* problem must never
-- become *our* error popup.
-- ---------------------------------------------------------------------------
local providers = {
    {
        key = "tsm",
        label = "TSM",
        -- TSM4+ exposes exactly one public surface: the TSM_API global.
        IsAvailable = function()
            return TSM_API ~= nil
                and TSM_API.GetCustomPriceValue ~= nil
                and TSM_API.ToItemString ~= nil
        end,
        GetCopper = function(itemLink)
            -- TSM speaks "item strings", not item links - convert first.
            local okString, itemString = pcall(TSM_API.ToItemString, itemLink)
            if not okString or not itemString then
                return nil
            end
            -- DBMarket = realm market value from the TSM desktop app's data.
            -- Chosen over DBMinBuyout because a single lowball listing should
            -- not decide whether we warn about a valuable item.
            local okPrice, copper = pcall(TSM_API.GetCustomPriceValue, "DBMarket", itemString)
            if okPrice and type(copper) == "number" and copper > 0 then
                return copper
            end
            return nil
        end,
    },
    {
        key = "auctionator",
        label = "Auctionator",
        IsAvailable = function()
            return Auctionator ~= nil
                and Auctionator.API ~= nil
                and Auctionator.API.v1 ~= nil
                and Auctionator.API.v1.GetAuctionPriceByItemLink ~= nil
        end,
        GetCopper = function(itemLink)
            -- Returns copper or nil (nil also while its DB is still loading).
            local ok, copper = pcall(
                Auctionator.API.v1.GetAuctionPriceByItemLink, CALLER_ID, itemLink)
            if ok and type(copper) == "number" and copper > 0 then
                return copper
            end
            return nil
        end,
    },
}

-- ---------------------------------------------------------------------------
-- Public interface
-- ---------------------------------------------------------------------------

-- Main entry point: Prices.GetValue(itemLink)
--   -> copper, sourceKey, sourceLabel   (first provider with a usable value)
--   -> nil                              (no provider available / no data)
-- Providers are asked in table order, so the priority lives in ONE place.
function Prices.GetValue(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end

    local now = GetTime()
    local hit = cache[itemLink]
    if hit and now < hit.expires then
        return hit.copper, hit.sourceKey, hit.sourceLabel
    end

    for _, provider in ipairs(providers) do
        if provider.IsAvailable() then
            local copper = provider.GetCopper(itemLink)
            if copper then
                CacheResult(itemLink, {
                    copper = copper,
                    sourceKey = provider.key,
                    sourceLabel = provider.label,
                    expires = now + CACHE_TTL,
                })
                return copper, provider.key, provider.label
            end
        end
    end

    -- Negative results are cached too: "no data" is the most common answer
    -- on a client without price addons, and it should cost nothing.
    CacheResult(itemLink, { expires = now + CACHE_TTL })
    return nil
end

-- True if at least one price source is installed and answering - the UI uses
-- this to decide whether price settings/warnings should be shown at all.
function Prices.HasAnySource()
    for _, provider in ipairs(providers) do
        if provider.IsAvailable() then
            return true
        end
    end
    return false
end

-- One status line per provider for the /deh check self-diagnostic.
-- Returns e.g. { { key = "tsm", label = "TSM", available = true }, ... }
function Prices.GetProviderStatus()
    local status = {}
    for _, provider in ipairs(providers) do
        status[#status + 1] = {
            key = provider.key,
            label = provider.label,
            available = provider.IsAvailable() and true or false,
        }
    end
    return status
end

-- Formats copper as a compact, locale-aware gold string for tags/warnings.
-- Deliberately gold-only: the warning threshold thinks in gold, and silver/
-- copper digits are visual noise at "is this worth 5000g?" scale.
function Prices.FormatGold(copper)
    if type(copper) ~= "number" then
        return ""
    end
    local gold = math.floor(copper / 10000)
    if BreakUpLargeNumbers then
        return tostring(BreakUpLargeNumbers(gold)) .. " g"
    end
    if gold >= 1000 then
        -- Older-client fallback for the two locales shipped by this addon.
        local separator = GetLocale and GetLocale() == "deDE" and "." or ","
        local formatted = tostring(gold)
        formatted = formatted:reverse():gsub("(%d%d%d)", "%1" .. separator):reverse()
        if formatted:sub(1, 1) == separator then
            formatted = formatted:sub(2)
        end
        return formatted .. " g"
    end
    return gold .. " g"
end

-- Gold amount followed by the in-game gold coin icon, for compact list tags
-- where the coin reads faster than a " g" suffix. Uses Blizzard's own money
-- texture (exists on Retail and Classic), sized to the surrounding font (:0).
function Prices.FormatGoldIcon(copper)
    if type(copper) ~= "number" then
        return ""
    end
    local gold = math.floor(copper / 10000)
    local number = BreakUpLargeNumbers and tostring(BreakUpLargeNumbers(gold)) or tostring(gold)
    return number .. " |TInterface\\MoneyFrame\\UI-GoldIcon:0|t"
end

-- Manual cache reset (e.g. for testing via /deh check, or after the user
-- visits the AH and wants fresh numbers immediately).
function Prices.ClearCache()
    wipe(cache)
    cacheCount=0
end
