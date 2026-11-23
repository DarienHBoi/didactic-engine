local _, S = ...
S.MailLog = {}
local M = S.MailLog

-- Mail log: every incoming mail that brings gold or items, logged when first seen, marked collected later.
-- Pure logic; the client is reached only through M.readInbox(api, ...), which guards every call.
M.MAX = 2000
-- Seconds the same mail's estimated expiry may drift between visits (days left may be rounded by the client).
-- Closest expiry wins, one entry per mail, so identical mails still count separately.
M.TOL = 36 * 3600

M.KIND_LABEL = {
    ah_sold = "AH sale", ah_won = "AH bought", ah_outbid = "AH outbid", ah_return = "AH returned",
    cod = "CoD payment", player = "From player", other = "Other",
}

-- Subject formats from the client's global strings (English fallback for any that are missing).
local SUBJECTS = {
    { "AUCTION_SOLD_MAIL_SUBJECT", "Auction successful: %s", "ah_sold" },
    { "AUCTION_WON_MAIL_SUBJECT", "Auction won: %s", "ah_won" },
    { "AUCTION_OUTBID_MAIL_SUBJECT", "Outbid on %s", "ah_outbid" },
    { "AUCTION_EXPIRED_MAIL_SUBJECT", "Auction expired: %s", "ah_return", "expired" },
    { "AUCTION_REMOVED_MAIL_SUBJECT", "Auction cancelled: %s", "ah_return", "cancelled" },
    { "COD_PAYMENT", "COD Payment: %s", "cod" },
}

local function toPattern(fmt)
    local s = fmt:gsub("%%%d%$s", "\001"):gsub("%%s", "\001")
    s = s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. s:gsub("\001", "(.+)") .. "$"
end

function M.patterns(G)
    G = G or {}
    local out = {}
    for _, d in ipairs(SUBJECTS) do
        local fmt = G[d[1]]
        if type(fmt) ~= "string" or not fmt:find("%%") then fmt = d[2] end
        out[#out + 1] = { pattern = toPattern(fmt), kind = d[3], sub = d[4] }
    end
    return out
end

local function subjectMatch(subject, P)
    if type(subject) ~= "string" then return nil end
    for _, p in ipairs(P or M.patterns()) do
        local cap = subject:match(p.pattern)
        if cap then return p.kind, cap end
    end
    return nil
end

-- "expired" or "cancelled" for an AH return mail's subject, else nil.
function M.returnKind(subject, P)
    if type(subject) ~= "string" then return nil end
    for _, p in ipairs(P or M.patterns()) do
        if p.sub and subject:match(p.pattern) then return p.sub end
    end
    return nil
end

function M.classify(m, P)
    if m.wasReturned then return "other" end
    local inv = m.invoiceType or (m.invoice and m.invoice.invoiceType)
    if inv == "seller" or inv == "seller_temp_invoice" then return "ah_sold" end
    if inv == "buyer" then return "ah_won" end
    local kind = subjectMatch(m.subject, P)
    if kind then return kind end
    return m.canReply and "player" or "other"
end

function M.itemName(m, P)
    local inv = m.invoice and m.invoice.itemName
    if type(inv) == "string" and inv ~= "" then return inv end
    local _, cap = subjectMatch(m.subject, P)
    if cap then return (cap:gsub("%s*%(%d+%)$", "")) end
    return nil
end

-- The itemID of what the mail is about: invoice itemID, an attachment link, else opts.resolve(name) (guarded).
function M.itemIDOf(m, name, resolve)
    local inv = m.invoice and m.invoice.itemID
    if type(inv) == "number" and inv > 0 then return inv end
    for _, it in ipairs(m.items or {}) do
        local id = type(it.link) == "string" and it.link:match("|Hitem:(%d+)")
        if id then return tonumber(id) end
    end
    if name and type(resolve) == "function" then
        local ok, id = pcall(resolve, name)
        if ok and type(id) == "number" and id > 0 then return id end
    end
    return nil
end

-- Stack size from "(20)" at the end of the subject, else the invoice count; nil when unknown.
function M.unitsOf(m)
    local n = type(m.subject) == "string" and m.subject:match("%((%d+)%)%s*$")
    if n then return tonumber(n) end
    local c = m.invoice and m.invoice.count
    if type(c) == "number" and c > 0 then return c end
    return nil
end

local function num(v) return (type(v) == "number" and v == v and v > -math.huge and v < math.huge) and v or 0 end

local function hasStuff(m) return num(m.money) > 0 or #(m.items or {}) > 0 end

local function book(log)
    log.entries = log.entries or {}
    log.all = log.all or { ah = 0, players = 0, ahCount = 0, playerCount = 0 }
    log.sold = log.sold or {}
    return log
end

local function received(e)
    local dep = e.invoice and num(e.invoice.deposit) or 0
    return math.max(0, num(e.money) - dep)
end

local function isPlayerIncome(kind) return kind == "player" or kind == "cod" end

local function newEntry(log, m, now, opts)
    local kind = M.classify(m, opts.patterns)
    local items = {}
    for _, it in ipairs(m.items or {}) do
        items[#items + 1] = { link = it.link, count = it.count, name = it.name, icon = it.icon }
    end
    local e = {
        kind = kind, sender = m.sender, subject = m.subject, item = M.itemName(m, opts.patterns),
        money = num(m.money), cod = num(m.cod), items = items, invoice = m.invoice,
        seen = now, expires = m.expires, char = opts.char,
        left = { money = num(m.money), items = #items },
    }
    e.itemID = M.itemIDOf(m, e.item, opts.resolve)
    e.units = M.unitsOf(m)
    local all = log.all
    if kind == "ah_sold" then
        all.ah, all.ahCount = all.ah + e.money, all.ahCount + 1
        if e.item then
            local k = e.item:lower()
            local r = log.sold[k] or { count = 0, total = 0 }
            r.count, r.total = r.count + 1, r.total + received(e)
            log.sold[k] = r
        end
    elseif isPlayerIncome(kind) then
        all.players, all.playerCount = all.players + e.money, all.playerCount + 1
    end
    log.entries[#log.entries + 1] = e
    return e
end

local function sameMail(e, m)
    if e.gone or e.sender ~= m.sender or e.subject ~= m.subject then return nil end
    if num(m.money) > e.left.money or #(m.items or {}) > e.left.items then return nil end
    if num(m.cod) ~= e.cod and num(m.cod) ~= 0 then return nil end
    if e.expires == nil and m.expires == nil then return 0 end
    if e.expires == nil or m.expires == nil then return nil end
    local d = math.abs(e.expires - m.expires)
    return d <= M.TOL and d or nil
end

local function markCollected(e, now)
    e.left.money, e.left.items = 0, 0
    e.collected = e.collected or now
end

-- One read of the inbox. session is a table the caller keeps for one mailbox visit (reset on open);
-- only mails seen earlier in the same visit are judged when they disappear.
-- opts = { patterns, char }. Returns { added, collected, skipped }.
function M.scan(log, mails, now, session, opts)
    opts = opts or {}
    book(log)
    session = session or {}
    local res = { added = 0, collected = 0 }
    local prev = session.prev or {}
    if #mails == 0 and #prev > 1 then res.skipped = true; return res end

    -- Every compatible (mail, entry) pair, closest expiry first, then assign one to one.
    local pairs_ = {}
    local entries = log.entries
    for mi, m in ipairs(mails) do
        for ei = #entries, 1, -1 do
            local d = sameMail(entries[ei], m)
            if d then pairs_[#pairs_ + 1] = { d = d, mi = mi, ei = ei } end
        end
    end
    table.sort(pairs_, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        if a.mi ~= b.mi then return a.mi < b.mi end
        return a.ei < b.ei
    end)
    local mailTo, taken = {}, {}
    for _, p in ipairs(pairs_) do
        if not mailTo[p.mi] and not taken[p.ei] then mailTo[p.mi] = p.ei; taken[p.ei] = true end
    end

    local claimed = {}
    for mi, m in ipairs(mails) do
        local ei = mailTo[mi]
        if ei then
            local e = entries[ei]
            claimed[e] = true
            if num(m.money) < e.left.money then e.left.money = num(m.money); e.goldAt = e.goldAt or now end
            local n = #(m.items or {})
            if n < e.left.items then e.left.items = n; e.itemsAt = e.itemsAt or now end
            if e.invoice == nil and m.invoice then e.invoice = m.invoice end
            if not e.collected and e.left.money == 0 and e.left.items == 0 then
                e.collected = now
                res.collected = res.collected + 1
            end
        end
    end
    local now_claimed = {}
    for e in pairs(claimed) do now_claimed[#now_claimed + 1] = e end

    -- Mails seen earlier this visit that are gone now.
    for _, e in ipairs(prev) do
        if not claimed[e] and not e.gone then
            if e.returned then
                e.gone = "returned"
            elseif e.collected then
                e.gone = "collected"
            elseif e.expires and e.expires <= now + 120 then
                e.gone = "expired"
            else
                markCollected(e, now)
                e.gone = "collected"
                res.collected = res.collected + 1
            end
        end
    end
    -- Anything past its expiry and not in the inbox has expired (seen or not this visit).
    if #mails > 0 then
        for _, e in ipairs(entries) do
            if not e.gone and not claimed[e] and e.expires and e.expires < now then
                e.gone = e.collected and "collected" or "expired"
            end
        end
    end

    for mi, m in ipairs(mails) do
        if not mailTo[mi] and hasStuff(m) then
            local e = newEntry(log, m, now, opts)
            now_claimed[#now_claimed + 1] = e
            res.added = res.added + 1
        end
    end
    while #entries > M.MAX do table.remove(entries, 1) end
    session.prev = now_claimed
    return res
end

-- The mail about to be returned to its sender (from a ReturnInboxItem hook).
function M.markReturned(log, m, now)
    if not (log and log.entries and m) then return nil end
    local best, bestD
    for _, e in ipairs(log.entries) do
        local d = sameMail(e, m)
        if d and (bestD == nil or d < bestD) then best, bestD = e, d end
    end
    if best then best.returned = now end
    return best
end

-- Gold in by period: today (since dayStart), the last 7 days, all time (running totals).
function M.totals(log, now, dayStart)
    local t = { today = { ah = 0, players = 0 }, week = { ah = 0, players = 0 }, all = { ah = 0, players = 0 } }
    if not log then return t end
    local all = log.all or {}
    t.all.ah, t.all.players = all.ah or 0, all.players or 0
    local weekStart = now - 7 * 86400
    for _, e in ipairs(log.entries or {}) do
        local field = (e.kind == "ah_sold" and "ah") or (isPlayerIncome(e.kind) and "players") or nil
        if field and e.seen then
            if e.seen >= weekStart then t.week[field] = t.week[field] + e.money end
            if dayStart and e.seen >= dayStart then t.today[field] = t.today[field] + e.money end
        end
    end
    return t
end

-- All-time gold from AH sales and players (shown beside service earnings, not mixed into them).
function M.income(log)
    local a = log and log.all
    return a and ((a.ah or 0) + (a.players or 0)) or 0
end

local function waiting(e) return not e.collected and not e.gone end

function M.uncollectedAH(log)
    local sum = 0
    for _, e in ipairs(log and log.entries or {}) do
        if e.kind == "ah_sold" and waiting(e) then sum = sum + (e.left and e.left.money or 0) end
    end
    return sum
end

function M.waiting(e) return waiting(e) end

-- Mails still waiting in the mailbox (not collected, not gone).
function M.waitingCount(log)
    local n = 0
    for _, e in ipairs(log and log.entries or {}) do if waiting(e) then n = n + 1 end end
    return n
end

-- Sold on AH for a recipe's crafted item: count, total received, average (0s when none).
function M.soldFor(log, recipe)
    if not (log and log.sold and recipe) then return 0, 0, 0 end
    local name = type(recipe.resultLink) == "string" and recipe.resultLink:match("%[(.-)%]") or recipe.name
    local r = type(name) == "string" and log.sold[name:lower()]
    if not r or r.count == 0 then return 0, 0, 0 end
    return r.count, r.total, math.floor(r.total / r.count + 0.5)
end

local FILTERS = {
    all = function() return true end,
    ah = function(e) return e.kind == "ah_sold" end,
    returns = function(e) return e.kind == "ah_outbid" or e.kind == "ah_return" end,
    players = function(e) return isPlayerIncome(e.kind) end,
    uncollected = waiting,
}
M.FILTER_ORDER = { "all", "ah", "returns", "players", "uncollected" }
M.FILTER_LABEL = { all = "All", ah = "AH sales", returns = "Returns", players = "Players", uncollected = "Uncollected" }

local function matches(e, q)
    local function has(s) return type(s) == "string" and s:lower():find(q, 1, true) ~= nil end
    if has(e.item) or has(e.sender) or has(e.subject) then return true end
    for _, it in ipairs(e.items or {}) do
        if has(it.name) or has(it.link) then return true end
    end
    return false
end

-- Entries for one filter and optional search text, newest first.
function M.filter(log, mode, search)
    local out = {}
    local keep = FILTERS[mode or "all"] or FILTERS.all
    local q = type(search) == "string" and search:lower():match("^%s*(.-)%s*$") or ""
    local list = log and log.entries or {}
    for i = #list, 1, -1 do
        local e = list[i]
        if keep(e) and (q == "" or matches(e, q)) then out[#out + 1] = e end
    end
    return out
end

-- Reads the open inbox through api (the client's globals in game). Every call is guarded.
function M.readInbox(api, now, P)
    local out = {}
    local function call(name, ...)
        local fn = api[name]
        if type(fn) ~= "function" then return false end
        return pcall(fn, ...)
    end
    local ok, n = call("GetInboxNumItems")
    if not ok or type(n) ~= "number" then return out end
    local maxA = type(api.ATTACHMENTS_MAX_RECEIVE) == "number" and api.ATTACHMENTS_MAX_RECEIVE or 16
    for i = 1, n do
        local h = { call("GetInboxHeaderInfo", i) }
        if h[1] then
            local sender, subject, money, cod, daysLeft, itemCount = h[4], h[5], h[6], h[7], h[8], h[9]
            local m = {
                sender = type(sender) == "string" and sender or "?",
                subject = type(subject) == "string" and subject or "",
                money = num(money), cod = num(cod),
                expires = (type(daysLeft) == "number" and daysLeft == daysLeft) and (now + math.floor(daysLeft * 86400)) or nil,
                index = i, wasReturned = h[11] == true, canReply = h[13] == true, items = {},
            }
            if type(itemCount) ~= "number" or itemCount > 0 then
                for a = 1, maxA do
                    local r = { call("GetInboxItem", i, a) }
                    if r[1] and (r[2] ~= nil or r[3] ~= nil) then
                        local okL, link = call("GetInboxItemLink", i, a)
                        m.items[#m.items + 1] = {
                            name = type(r[2]) == "string" and r[2] or nil,
                            icon = r[4], count = type(r[5]) == "number" and r[5] or 1,
                            link = okL and type(link) == "string" and link or nil,
                        }
                    end
                end
            end
            if not m.canReply then
                local v = { call("GetInboxInvoiceInfo", i) }
                if v[1] and type(v[2]) == "string" then
                    m.invoice = { invoiceType = v[2], itemName = v[3], playerName = v[4], bid = num(v[5]),
                                  buyout = num(v[6]), deposit = num(v[7]), consignment = num(v[8]) }
                end
            end
            out[#out + 1] = m
        end
    end
    return out
end
