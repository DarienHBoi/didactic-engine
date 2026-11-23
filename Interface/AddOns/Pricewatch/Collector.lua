local _, P = ...
P.Collector = {}
local Co = P.Collector

-- Copies Auctionator's daily figures and posting records for every watched item into the store. Auctionator's
-- 21 days are copied on the first run (backfill); later runs are idempotent. One failing item never stops the rest.
-- deps = { watch() -> ids, history(id), posts(id), hour() }
function Co.run(db, deps, today)
    local res = { items = 0, failed = 0 }
    if type(db) ~= "table" or type(db.items) ~= "table" or type(deps) ~= "table" then return res end
    local okW, ids = pcall(deps.watch or function() return {} end)
    if not okW or type(ids) ~= "table" then return res end
    local hour
    if deps.hour then
        local ok, h = pcall(deps.hour)
        if ok then hour = h end
    end
    for _, id in ipairs(ids) do
        res.items = res.items + 1
        local okH, rows = pcall(deps.history, id)
        local okP, posts = pcall(deps.posts, id)
        if okH and okP then
            P.Store.record(db, id, rows, posts, today, hour)
        else
            res.failed = res.failed + 1
        end
    end
    P.Store.prune(db, today)
    return res
end
