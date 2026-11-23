local _, P = ...
P.name = "Pricewatch"
-- Thresholds in one place (design: "changeable in one place").
P.Config = {
    MAX_ITEMS = 2000,     -- watched items kept
    MAX_DAYS = 365,       -- days of history kept per item
    DROP_UNSEEN_DAYS = 180, -- items not seen for this long are dropped
    MAX_POSTS = 400,      -- own listing records kept per item
    FRESH_DAYS = 1,       -- a price this many scan days old (or less) counts as fresh
    MARKET_DAYS = 14,       -- Market: scan days that count
    MARKET_HALF_LIFE = 2.2, -- Market: a day this much older counts half as much
    AH_CUT = 0.05,
    DE_MARGIN_PCT = 0.10,   -- disenchant must beat the alternative by this fraction ...
    DE_MARGIN_COPPER = 500, -- ... and by at least this many copper (5s)
    DE_MIN_SAMPLES = 10,    -- disenchant logger: a bracket needs this many of your own disenchants before its observed rates replace
                            -- the table (a chosen floor: with 10 samples a 75% mat is known to about +-14%, better than a Classic guess)
    -- Expected value of listing on the AH (Recommend.lua): value = price after the cut x p(sell) - deposit x (1 - p(sell)).
    SELL_DEFAULT = 0.8,     -- p(sell) when there is neither your own sell rate (5+ outcomes) nor tracked market sell-through. A chosen
                            -- neutral prior, not measured: most items listed at the going price do sell on Classic, so it is above a
                            -- coin flip but never certain. Replace it with data as soon as either source has any.
    DEPOSIT_RATE_24H = 0.30, -- deposit estimate = vendor sell price x this, used only when the client gives no deposit. INFERRED from the
                            -- usual Classic faction-AH deposit (15% of vendor price at 12h, 30% at 24h, 60% at 48h); not verified on Forever.
    DEALS_MAX_AGE_DAYS = 1, -- deals tab: THE stale threshold: older prices are hidden unless "Include stale", then greyed with a red !
    TREND_DOWN = 0.05,      -- trend guard: now more than this under the 7-day average counts as falling
    TREND_FLOOR = 0.75,     -- trend guard: a falling mat is never valued under this share of now
    TREND_MIN_DAYS = 5,     -- trend guard: ZugHistory / Pricewatch history count as a 7-day only with this many distinct days
    POST_FLOOR = 0.9,       -- Post mats: never undercut below this share of the mat consensus price
    MAT_AGREE = 0.25,       -- mat prices: two sources within 25% agree (Value.matConsensus)
    -- Price resolver (Value.resolve, audit step 5): ZugDAQ first, the rest a sanity band. Owner 2026-11-21: log first, switch later.
    RESOLVE_USE = false,    -- valuation uses the resolver (default off until the owner has read /pricewatch resolve log)
    RESOLVE_LOG = true,     -- record items where the resolver and the old rule differ
    RESOLVE_LOG_PCT = 0.15, -- ... by more than this fraction (owner's figure)
    RESOLVE_LOG_MAX = 300,  -- items kept in the log
    RESOLVE_BAND = 2,       -- ZugDAQ more than this factor outside the other sources is flagged (never outvoted)
    RESOLVE_MEMO_SECS = 2,  -- one item is resolved at most once per this many seconds (one evaluation pass)
    AH_BUY_ROWS = false,    -- AH rows: also label each auction in the item buy list (off: the owner prefers the Browse column)
    ZUGH_THIN_DAYS = 7,     -- ZugHistory: own scan history under this many days uses the server 30-day median as Usual
    ZUGH_MIN_N = 3,         -- ZugHistory: at least this many priced days before its median is used or shown
    ZUG_STALE_DAYS = 3,     -- ZugDAQ data (Adapters.zug): older than this many days (its AH snapshot, else its file time) is not used
    ZUG_SELL_HALF = 1,      -- ZugDAQ sells/day at which a listing has a 50% chance to sell: p = perDay / (perDay + this). A chosen
                            -- saturating curve (1/day = 50%, 4/day = 80% = SELL_DEFAULT, never certain), not measured.
    TODAY_ROWS = 12,        -- Today view: rows shown
    TODAY_MIN_DAYS = 3,     -- Today view: scan days an item needs (fewer = thin data, dropped)
    TODAY_MAX_AGE = 3,      -- Today view: a price older than this many scan days is dropped
    HOLD_BELOW = 0.85,      -- Today view: price under this fraction of Market = Hold, not sell
    BAG_UNITS = 20,         -- Today view: a bag stack counts at most this many units
    DEALS_MIN_PROFIT = 500, -- Deals panel: default Min profit (copper)
    DEALS_THIN_DAYS = 3,    -- Deals panel: mats with fewer scan days than this get a red !
    DEALS_REBUILD_SECS = 0.25, -- Deals panel: rows are rebuilt at most this often while scanning
    DEALS_TIMEOUT_SECS = 8, -- Deals panel: give up on items the client never answers after this long
    DEALS_MAX_ROWS = 300,   -- Deals panel: rows kept
    FLIP_BELOW = 0.8,       -- Flip mode: Now must be at most this fraction of Market ("well under"; a chosen cut, not measured)
    FLIP_MIN_PER_DAY = 1,   -- Flip mode: at least this many sold per day (sold tracker, else ZugDAQ) so the relist is likely to sell
    FLIP_MAX = 1000,        -- Flip mode: candidates kept per Deals pass
    -- Sold tracker (Market.lua, Rescan.lua)
    MARKET_KEEP_DAYS = 60,  -- day aggregates kept per item
    MARKET_MAX_ROWS = 200,  -- listings fingerprinted per item (the cheapest)
    MARKET_MAX_ITEMS = 500, -- items tracked in total (least recently scanned dropped first)
    MARKET_PRICES = 20,     -- sold prices kept per item per day
    MARKET_MIN_SCANS = 3,   -- fewer real comparisons (scan vs the previous one, under a day apart) = thin data, shown as '-'
    MARKET_MIN_GAP = 120,   -- seconds: a repeat search sooner than this is not counted as another scan
    MARKET_MAX_GAP = 86400, -- seconds: a longer gap between scans says nothing (the longest listing lasts 24 h)
    RESCAN_MAX = 40,        -- Rescan watched: items per click
    RESCAN_TIMEOUT = 5,     -- Rescan watched: seconds to wait for one item
    RESCAN_PAGES = 3,       -- Rescan watched: extra result pages asked for per item
}
