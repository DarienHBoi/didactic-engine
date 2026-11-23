-- Ring the Bell: wire codec for GUILD addon messages ("1|K|amount|spellID|t|player|spell|target|class|secs"; 0.1 sent only the first 8 fields).
local addonName, RB = ...
local L = RB.L
local W = {}
RB.W = W

W.PREFIX = "RingTheBell"
W.VERSION = "1"
W.MAX = 255

local function clean(s)
    return (tostring(s or ""):gsub("[|\r\n]", ""))
end

-- cut s to at most n bytes without splitting a UTF-8 character
local function cutBytes(s, n)
    if n <= 0 then return "" end
    if #s <= n then return s end
    while n > 0 do
        local b = s:byte(n + 1)
        if b and b >= 0x80 and b <= 0xBF then n = n - 1 else break end
    end
    return s:sub(1, n)
end

local function int(n)
    n = tonumber(n) or 0
    return math.floor(n)
end

function W.encode(kind, rec)
    if kind == "Q" then return W.VERSION .. "|Q" end
    if kind ~= "C" and kind ~= "R" then return nil end
    local player, spell, target = clean(rec.player), clean(rec.spell), clean(rec.target)
    local spellID = rec.spellID and tostring(int(rec.spellID)) or ""
    local class = L.validClass(rec.class) or ""
    local secs = L.validSecs(rec.secs)
    secs = secs and tostring(secs) or ""
    local function build()  -- class/secs are short and sit last: the trim below only ever cuts target, then spell
        return table.concat({ W.VERSION, kind, int(rec.amount), spellID, int(rec.t), player, spell, target, class, secs }, "|")
    end
    local msg = build()
    if #msg > W.MAX then
        local over = #msg - W.MAX
        local cut = math.min(over, #target)
        target = cutBytes(target, #target - cut); over = over - cut
        if over > 0 then spell = cutBytes(spell, #spell - over) end
        msg = build()
        if #msg > W.MAX then msg = cutBytes(msg, W.MAX) end
    end
    return msg
end

function W.encodeVersion(ver, push)
    return table.concat({ W.VERSION, "V", clean(ver), push and "1" or "0" }, "|")
end

local function split(msg)
    local t = {}
    for part in (msg .. "|"):gmatch("([^|]*)|") do t[#t + 1] = part end
    return t
end

function W.decode(msg)
    if type(msg) ~= "string" or msg == "" then return nil end
    local f = split(msg)
    if f[1] ~= W.VERSION then return nil end
    local kind = f[2]
    if kind == "Q" then return "Q", {} end
    if kind == "V" then
        if not f[3] or f[3] == "" or (f[4] ~= "0" and f[4] ~= "1") then return nil end
        return "V", { version = f[3], push = f[4] == "1" }
    end
    if kind ~= "C" and kind ~= "R" then return nil end
    if #f ~= 8 and #f ~= 10 then return nil end
    local function uint(str, maxLen)
        if not str:match("^%d+$") or #str > maxLen then return nil end
        return tonumber(str)
    end
    local amount, t = uint(f[3], 15), uint(f[5], 15)
    if not amount or amount <= 0 or not t then return nil end
    if f[6] == "" then return nil end
    local spellID = nil
    if f[4] ~= "" then
        spellID = uint(f[4], 10)
        if not spellID or spellID <= 0 then return nil end
    end
    local rec = { amount = amount, spellID = spellID, t = t, player = f[6], spell = f[7], target = f[8] }
    if #f == 10 then
        rec.class = L.validClass(f[9])
        if f[10]:match("^%d+$") and #f[10] <= 6 then rec.secs = L.validSecs(tonumber(f[10])) end
    end
    rec.id = L.newId(rec.player, rec.t, rec.amount)
    return kind, rec
end
