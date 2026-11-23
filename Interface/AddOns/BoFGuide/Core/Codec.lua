-- Import strings, made by `forever guide-pack` (the format is described in src/forever/guide/codec.py):
--   !BOFG1!<base64 of: "BG", version, flags, checksum (4 bytes), tag hint (2 bytes), body>
-- The body is the pack as JSON, deflated (version 2) and scrambled for one BattleTag. It is inflated and parsed here as
-- data; nothing in it is ever run. Only plain arithmetic and byte-sized XORs (a small nibble table), so it doesn't
-- depend on the game's bit library.
local _, ns = ...

local Codec = {}
ns.Codec = Codec

local byte, char, sub, find, floor, concat = string.byte, string.char, string.sub, string.find, math.floor, table.concat
local PREFIX = '!BOFG1!'
local VERSIONS = { [1] = true, [2] = true }   -- 1: plain JSON, 2: deflated
local M32, SEED_MIX = 4294967296, 2654435769
local MAX_DEPTH = 64

-- ------------------------------------------------------------------------------------------------------ byte math
local NIB = {}
for a = 0, 15 do
  NIB[a] = {}
  for b = 0, 15 do
    local r, p, x, y = 0, 1, a, b
    for _ = 1, 4 do
      if x % 2 ~= y % 2 then r = r + p end
      x, y, p = floor(x / 2), floor(y / 2), p * 2
    end
    NIB[a][b] = r
  end
end
local function xor8(a, b)
  return NIB[a % 16][b % 16] + 16 * NIB[floor(a / 16)][floor(b / 16)]
end

-- A long decode gives the frame back now and then (Nov 4, launch day: the game stops a script that runs too long, and
-- opening a paid pack took about half a second). Codec.pause is set only while Core/Paid.lua opens a pack in its own
-- coroutine, and calls coroutine.yield when that frame's share is used up; otherwise it's nil and everything decodes in
-- one go, as before. The loops call it every few thousand steps.
Codec.pause = nil

--- FNV-1a (32 bit) of a string or a byte table
function Codec.fnv1a(data)
  local h = 2166136261
  local isStr = type(data) == 'string'
  local pause = Codec.pause
  for i = 1, #data do
    if pause and i % 4096 == 0 then pause() end
    local b = isStr and byte(data, i) or data[i]
    local lo = h % 256
    h = h - lo + xor8(lo, b)
    h = ((h % 256) * 16777216 + h * 403) % M32   -- h * 16777619, kept exact
  end
  return h
end

--- the key for a BattleTag: A-Z lowercased, like the Python side
function Codec.TagKey(tag)
  if type(tag) ~= 'string' or tag == '' then return nil end
  tag = tag:match('^%s*(.-)%s*$'):gsub('[A-Z]', string.lower)
  return Codec.fnv1a(tag)
end

local function unscramble(t, first, key)
  local x = (key + SEED_MIX) % M32
  for i = first, #t do
    x = (x * 1664525 + 1013904223) % M32
    t[i] = xor8(t[i], floor(x / 16777216))
  end
end

-- --------------------------------------------------------------------------------------------------------- base64
local B64 = {}
do
  local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  for i = 1, 64 do B64[byte(alphabet, i)] = i - 1 end
end

local function unbase64(s)
  local out, n = {}, 0
  local len = #s
  if len % 4 ~= 0 then return nil end
  local pause = Codec.pause
  for i = 1, len, 4 do
    if pause and i % 16384 == 1 then pause() end
    local a, b, c, d = byte(s, i, i + 3)
    local va, vb = B64[a], B64[b]
    local vc, vd = c ~= 61 and B64[c] or 0, d ~= 61 and B64[d] or 0   -- 61 is '='
    if not (va and vb and vc and vd) then return nil end
    if (c == 61 or d == 61) and i + 3 ~= len then return nil end
    local v = va * 262144 + vb * 4096 + vc * 64 + vd
    n = n + 1 out[n] = floor(v / 65536)
    if c ~= 61 then n = n + 1 out[n] = floor(v / 256) % 256 end
    if d ~= 61 then n = n + 1 out[n] = v % 256 end
  end
  return out
end

local function bytesToString(t, first)
  local parts = {}
  local pause = Codec.pause
  for i = first, #t, 4096 do
    if pause then pause() end
    parts[#parts + 1] = char(unpack(t, i, math.min(i + 4095, #t)))
  end
  return concat(parts)
end

-- the pieces Core/Paid.lua shares (the paid packs in the download, docs/guide/paid-keys.md)
Codec.Xor8, Codec.Unbase64, Codec.BytesToString = xor8, unbase64, bytesToString

-- -------------------------------------------------------------------------------------------------------- inflate
-- Raw DEFLATE (RFC 1951), written from the RFC: stored, fixed-Huffman and dynamic-Huffman blocks. Bits come off each
-- byte low first; Huffman codes are canonical and read a bit at a time, most significant first. Anything malformed
-- raises an error, which Decode turns into 'damaged'. The code rules are zlib's: the code-length code must be complete,
-- and a literal/length or distance code may be incomplete only when it is a single 1-bit code; nothing may follow the
-- final block.
Codec.MAX_OUT = 4 * 1024 * 1024   -- 32 times the paid pack; a Lua table slot is about 16 bytes

local POW2 = {}
for i = 0, 32 do POW2[i] = 2 ^ i end
local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163,
                   195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                    4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CL_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

--- a canonical Huffman code from code lengths (lengths[symbol], symbols 0 .. n - 1): how many codes of each length,
--- and the symbols in code order. kind: 'codes' (the code-length code), 'lens' (literal/length or distance), nil for
--- the fixed codes
local function huffman(lengths, n, kind)
  local count, offs, symbols = {}, {}, {}
  for len = 0, 15 do count[len] = 0 end
  local longest = 0
  for sym = 0, n - 1 do
    local len = lengths[sym] or 0
    count[len] = count[len] + 1
    if len > longest then longest = len end
  end
  local left = 1
  for len = 1, 15 do
    left = left * 2 - count[len]
    if left < 0 then error('over-subscribed code') end
  end
  if kind and left > 0 and longest > 0 and (kind == 'codes' or longest ~= 1) then error('incomplete code') end
  offs[1] = 0
  for len = 1, 14 do offs[len + 1] = offs[len] + count[len] end
  for sym = 0, n - 1 do
    local len = lengths[sym] or 0
    if len > 0 then symbols[offs[len]] = sym offs[len] = offs[len] + 1 end
  end
  return { count = count, symbols = symbols }
end

local fixedLit, fixedDist
local function fixedCodes()
  if not fixedLit then
    local l = {}
    for sym = 0, 287 do l[sym] = sym < 144 and 8 or sym < 256 and 9 or sym < 280 and 7 or 8 end
    local d = {}
    for sym = 0, 29 do d[sym] = 5 end
    fixedLit, fixedDist = huffman(l, 288), huffman(d, 30)
  end
  return fixedLit, fixedDist
end

--- inflate a byte table from index first: the bytes it holds, as a table
function Codec.Inflate(inp, first)
  local pos, last, max = first or 1, #inp, Codec.MAX_OUT
  local bitbuf, bitcnt = 0, 0
  local out, n = {}, 0
  local pause, ticks = Codec.pause, 0

  local function need(k)   -- the next k bits, low first
    while bitcnt < k do
      if pos > last then error('out of input') end
      bitbuf = bitbuf + inp[pos] * POW2[bitcnt]
      bitcnt, pos = bitcnt + 8, pos + 1
    end
    local v = bitbuf % POW2[k]
    bitbuf, bitcnt = (bitbuf - v) / POW2[k], bitcnt - k
    return v
  end

  local function decode(h)   -- one symbol: the code's bits arrive most significant first
    local code, firstCode, index = 0, 0, 0
    local count, symbols = h.count, h.symbols
    for len = 1, 15 do
      if bitcnt == 0 then
        if pos > last then error('out of input') end
        bitbuf, bitcnt, pos = inp[pos], 8, pos + 1
      end
      local b = bitbuf % 2
      bitbuf, bitcnt = (bitbuf - b) / 2, bitcnt - 1
      code = code + b
      local c = count[len]
      if code - c < firstCode then return symbols[index + code - firstCode] end
      index = index + c
      firstCode = (firstCode + c) * 2
      code = code * 2
    end
    error('bad code')
  end

  local function codes(lit, dist)
    while true do
      if pause then
        ticks = ticks + 1
        if ticks >= 4096 then ticks = 0 pause() end
      end
      local sym = decode(lit)
      if sym < 256 then
        if n >= max then error('too big') end
        n = n + 1
        out[n] = sym
      elseif sym == 256 then
        return
      else
        sym = sym - 256
        if sym > 29 then error('bad length code') end
        local len = LEN_BASE[sym] + need(LEN_EXTRA[sym])
        local d = decode(dist) + 1
        if d > 30 then error('bad distance code') end
        d = DIST_BASE[d] + need(DIST_EXTRA[d])
        if d > n then error('distance before the start') end
        if n + len > max then error('too big') end
        local from = n - d
        for i = 1, len do out[n + i] = out[from + i] end   -- byte by byte, so an overlapping copy repeats itself
        n = n + len
      end
    end
  end

  local function stored()
    bitbuf, bitcnt = 0, 0   -- the rest of the current byte (fewer than 8 bits are ever left over)
    if pos + 3 > last then error('out of input') end
    local len = inp[pos] + inp[pos + 1] * 256
    if len + inp[pos + 2] + inp[pos + 3] * 256 ~= 65535 then error('bad stored length') end
    pos = pos + 4
    if pos + len - 1 > last then error('out of input') end
    if n + len > max then error('too big') end
    for i = 0, len - 1 do out[n + 1 + i] = inp[pos + i] end
    n, pos = n + len, pos + len
  end

  local function dynamic()
    local nlit, ndist, ncode = need(5) + 257, need(5) + 1, need(4) + 4
    if nlit > 286 or ndist > 30 then error('bad code counts') end
    local cl = {}
    for i = 1, 19 do cl[CL_ORDER[i]] = 0 end
    for i = 1, ncode do cl[CL_ORDER[i]] = need(3) end
    local clCode = huffman(cl, 19, 'codes')
    local all, idx, total = {}, 0, nlit + ndist
    while idx < total do
      local sym = decode(clCode)
      if sym < 16 then
        all[idx], idx = sym, idx + 1
      else
        local len, rep = 0, nil
        if sym == 16 then
          if idx == 0 then error('repeat with no length before it') end
          len, rep = all[idx - 1], 3 + need(2)
        elseif sym == 17 then rep = 3 + need(3)
        else rep = 11 + need(7) end
        if idx + rep > total then error('too many lengths') end
        for _ = 1, rep do all[idx], idx = len, idx + 1 end
      end
    end
    if (all[256] or 0) == 0 then error('no end-of-block code') end
    local lit, dist = {}, {}
    for i = 0, nlit - 1 do lit[i] = all[i] end
    for i = 0, ndist - 1 do dist[i] = all[nlit + i] end
    codes(huffman(lit, nlit, 'lens'), huffman(dist, ndist, 'lens'))
  end

  repeat
    local final, kind = need(1), need(2)
    if kind == 0 then stored()
    elseif kind == 1 then codes(fixedCodes())
    elseif kind == 2 then dynamic()
    else error('bad block type') end
  until final == 1
  if pos <= last then error('data after the end') end
  return out
end

--- inflate a string (the selftest's probe)
function Codec.InflateText(s)
  local t = {}
  for i = 1, #s do t[i] = byte(s, i) end
  return bytesToString(Codec.Inflate(t, 1), 1)
end

-- ----------------------------------------------------------------------------------------------------------- JSON
local ESC = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }

local function utf8(cp)
  if cp < 128 then return char(cp) end
  if cp < 2048 then return char(192 + floor(cp / 64), 128 + cp % 64) end
  if cp < 65536 then return char(224 + floor(cp / 4096), 128 + floor(cp / 64) % 64, 128 + cp % 64) end
  return char(240 + floor(cp / 262144), 128 + floor(cp / 4096) % 64, 128 + floor(cp / 64) % 64, 128 + cp % 64)
end

local parseValue

local function skip(s, i)
  local j = find(s, '[^ \t\r\n]', i)
  if not j then error('end of data') end
  return j
end

local function parseString(s, i)   -- i at the opening quote
  local parts, pos = {}, i + 1
  while true do
    local j = find(s, '["\\]', pos)
    if not j then error('unterminated string') end
    parts[#parts + 1] = sub(s, pos, j - 1)
    if byte(s, j) == 34 then return concat(parts), j + 1 end
    local e = sub(s, j + 1, j + 1)
    if e == 'u' then
      local cp = tonumber(sub(s, j + 2, j + 5), 16)
      if not cp then error('bad \\u escape') end
      pos = j + 6
      if cp >= 0xD800 and cp <= 0xDBFF and sub(s, pos, pos + 1) == '\\u' then
        local lo = tonumber(sub(s, pos + 2, pos + 5), 16)
        if lo and lo >= 0xDC00 and lo <= 0xDFFF then
          cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00)
          pos = pos + 6
        end
      end
      parts[#parts + 1] = utf8(cp)
    elseif ESC[e] then
      parts[#parts + 1] = ESC[e]
      pos = j + 2
    else
      error('bad escape')
    end
  end
end

local jsonTicks = 0
function parseValue(s, i, depth, pause)
  if pause then
    jsonTicks = jsonTicks + 1
    if jsonTicks >= 512 then jsonTicks = 0 pause() end
  end
  i = skip(s, i)
  local c = byte(s, i)
  if c == 123 then   -- {
    if depth > MAX_DEPTH then error('too deep') end
    local obj = {}
    i = skip(s, i + 1)
    if byte(s, i) == 125 then return obj, i + 1 end
    while true do
      if byte(s, i) ~= 34 then error('expected a key') end
      local k
      k, i = parseString(s, i)
      i = skip(s, i)
      if byte(s, i) ~= 58 then error('expected :') end
      local v
      v, i = parseValue(s, i + 1, depth + 1, pause)
      -- JSON keys are strings; ours that look like integers were numbers (quest and npc IDs)
      obj[find(k, '^%-?%d+$') and tonumber(k) or k] = v
      i = skip(s, i)
      local d = byte(s, i)
      if d == 125 then return obj, i + 1 end
      if d ~= 44 then error('expected , or }') end
      i = skip(s, i + 1)
    end
  elseif c == 91 then   -- [
    if depth > MAX_DEPTH then error('too deep') end
    local arr, n = {}, 0
    i = skip(s, i + 1)
    if byte(s, i) == 93 then return arr, i + 1 end
    while true do
      local v
      v, i = parseValue(s, i, depth + 1, pause)
      n = n + 1
      arr[n] = v   -- a null keeps its place (a hole), as in the bundled Lua packs
      i = skip(s, i)
      local d = byte(s, i)
      if d == 93 then return arr, i + 1 end
      if d ~= 44 then error('expected , or ]') end
      i = i + 1
    end
  elseif c == 34 then
    return parseString(s, i)
  elseif c == 116 and sub(s, i, i + 3) == 'true' then return true, i + 4
  elseif c == 102 and sub(s, i, i + 4) == 'false' then return false, i + 5
  elseif c == 110 and sub(s, i, i + 3) == 'null' then return nil, i + 4
  end
  local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
  if not num or num == '' then error('unexpected character at ' .. i) end
  local v = tonumber(num)
  if not v then error('bad number') end
  return v, i + #num
end

--- JSON text -> Lua value (errors on anything malformed)
function Codec.ParseJSON(s)
  local v, i = parseValue(s, 1, 0, Codec.pause)
  if find(s, '[^ \t\r\n]', i) then error('trailing data') end
  return v
end

-- --------------------------------------------------------------------------------------------------------- decode
--- an import string -> pack table, or nil and why: notpack | version | notag | account | damaged
function Codec.Decode(text, battletag)
  if type(text) ~= 'string' then return nil, 'notpack' end
  text = text:gsub('%s+', '')
  if sub(text, 1, #PREFIX) ~= PREFIX then return nil, 'notpack' end
  local t = unbase64(sub(text, #PREFIX + 1))
  if not t then return nil, 'damaged' end
  if #t < 10 or t[1] ~= 66 or t[2] ~= 71 then return nil, 'notpack' end   -- "BG"
  if not VERSIONS[t[3]] then return nil, 'version' end
  local flags = t[4]
  if flags >= 4 then return nil, 'version' end   -- a flag this version doesn't know
  local check = ((t[5] * 256 + t[6]) * 256 + t[7]) * 256 + t[8]
  local hint = t[9] * 256 + t[10]
  if flags % 2 == 1 then   -- bound to a BattleTag
    local key = Codec.TagKey(battletag)
    if not key then return nil, 'notag' end
    if floor(key / 65536) ~= hint then return nil, 'account' end
    unscramble(t, 11, key)
  end
  local body
  if floor(flags / 2) % 2 == 1 then   -- deflated
    local ok, out = pcall(Codec.Inflate, t, 11)
    if not ok then return nil, 'damaged' end
    body = out
  else
    body = {}
    for i = 11, #t do body[i - 10] = t[i] end
  end
  if Codec.fnv1a(body) ~= check then return nil, 'damaged' end
  local ok, pack = pcall(Codec.ParseJSON, bytesToString(body, 1))
  if not ok then return nil, 'damaged' end
  return pack
end
