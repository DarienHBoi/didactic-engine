-- NectarSellers pure logic. No WoW API here; every read of a result is guarded so a "secret" or
-- oddly shaped value gives a safe answer instead of an error inside the auction house.
local _, NS = ...
local L = {}
NS.Logic = L

L.GREEN   = { 0.25, 1.0, 0.25 }   -- your own listings
L.ALT     = { 0.55, 0.75, 1.0 }   -- another character on your account
L.GREY    = { 0.6, 0.6, 0.6 }     -- unknown seller
L.PLAIN   = { 0.9, 0.9, 0.9 }     -- a seller with one listing here
L.PALETTE = {                     -- sellers with 2+ listings; picked by a stable hash of the name
    { 1.0, 0.6, 0.2 },   -- orange
    { 1.0, 0.4, 1.0 },   -- magenta
    { 1.0, 0.9, 0.2 },   -- yellow
    { 0.3, 0.9, 1.0 },   -- cyan
    { 1.0, 0.45, 0.45 }, -- salmon
    { 0.7, 0.55, 1.0 },  -- violet
}
L.MAX_NAME = 12
L.UNKNOWN = "?"

-- t[k] when t is a plain table, nil otherwise or on error
local function get(t, k)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[k] end)
    if ok then return v end
end

-- s when it is a non-empty string that compares and concatenates without error
local function plainString(s)
    if type(s) ~= "string" then return nil end
    local ok, good = pcall(function() return s ~= "" and (s .. "") == s end)
    if ok and good then return s end
end

-- n when it is a finite plain number
local function plainNumber(n)
    if type(n) ~= "number" then return nil end
    local ok, good = pcall(function() return n == n and n > -math.huge and n < math.huge end)
    if ok and good then return n end
end

local function isTrue(v) return rawequal(v, true) end

local function len(t)
    if type(t) ~= "table" then return 0 end
    local ok, n = pcall(function() return #t end)
    return (ok and plainNumber(n)) or 0
end

function L.truncate(s, max)
    if type(s) ~= "string" then return "" end
    max = max or L.MAX_NAME
    local chars = {}
    for ch in s:gmatch("[%z\1-\127\192-\255][\128-\191]*") do chars[#chars + 1] = ch end
    if #chars <= max then return s end
    return table.concat(chars, "", 1, max - 1) .. ".."
end

-- Reads the fields we use. Returns first owner (plain string or nil), owner total, own flag, account flag, isMe.
local function read(info, myName)
    if type(info) ~= "table" then return nil, 0, false, false, false end
    local owners = get(info, "owners")
    local first = plainString(get(owners, 1))
    local total = plainNumber(get(info, "totalNumberOfOwners"))
    local n = len(owners)
    if not total or total < n then total = n end
    total = math.floor(total)
    local mine = isTrue(get(info, "containsOwnerItem"))
    local alt = isTrue(get(info, "containsAccountItem"))
    local me = plainString(myName)
    local isMe = first ~= nil and (first == "player" or (me ~= nil and first == me))
    return first, total, mine, alt, isMe
end

-- Text for the row and a fixed colour, or nil colour when the tint should decide.
function L.sellerText(info, myName)
    local first, total, mine, alt, isMe = read(info, myName)
    if first then
        if isMe or (mine and total <= 1) then
            if total > 1 then return "You +" .. (total - 1), L.GREEN end
            return "You", L.GREEN
        end
        if total > 1 then return L.truncate(first, L.MAX_NAME) .. " +" .. (total - 1), nil end
        return L.truncate(first, L.MAX_NAME), nil
    end
    if mine then return "You", L.GREEN end
    if alt then return "Alt", L.ALT end
    return L.UNKNOWN, L.GREY
end

-- Full name used to count listings per seller; nil when there is no single known seller.
function L.sellerKey(info, myName)
    local first, total, mine, alt, isMe = read(info, myName)
    if first then
        if isMe or (mine and total <= 1) then return total <= 1 and "You" or nil end
        if total > 1 then return nil end
        return first
    end
    if mine then return "You" end
    if alt then return "Alt" end
    return nil
end

function L.countBySeller(list, myName)
    local counts = {}
    if type(list) ~= "table" then return counts end
    local n = plainNumber(get(list, "n")) or len(list)
    if n > 10000 then n = 10000 end
    for i = 1, n do
        local key = L.sellerKey(get(list, i), myName)
        if key then counts[key] = (counts[key] or 0) + 1 end
    end
    return counts
end

local function hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

function L.tintFor(name, counts)
    name = plainString(name)
    if not name or type(counts) ~= "table" then return L.PLAIN end
    local c = plainNumber(rawget(counts, name))
    if not c or c < 2 then return L.PLAIN end
    return L.PALETTE[hash(name) % #L.PALETTE + 1]
end

function L.hex(c)
    local function b(x) return math.floor((tonumber(x) or 1) * 255 + 0.5) end
    return string.format("%02x%02x%02x", b(c[1]), b(c[2]), b(c[3]))
end

return L
