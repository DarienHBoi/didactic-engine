local _, S = ...
S.Match = {}

local GRADE = { minor = true, lesser = true, greater = true, major = true, superior = true, inferior = true, enchant = true }
local STOP = { to = true, of = true, the = true, ["and"] = true, ["for"] = true }
local SLOTS = {
    { key = "chest", words = { "chest" } },
    { key = "bracer", words = { "bracer", "bracers", "wrist", "wrists" } },
    { key = "gloves", words = { "gloves", "glove", "hands" } },
    { key = "boots", words = { "boots", "boot", "feet" } },
    { key = "cloak", words = { "cloak", "cloaks" } },
    { key = "shield", words = { "shield" } },
    { key = "two-handed", words = { "2h", "2handed", "twohand" } },
    { key = "one-handed", words = { "1h", "onehand" } },
    { key = "weapon", words = { "weapon", "weapons", "wep", "weap" } },
    { key = "ring", words = { "ring", "rings" } },
}

local function tokens(text)
    local out = {}
    for t in text:lower():gmatch("%w+") do out[#out + 1] = t end
    return out
end

local function tailWords(recipe)
    local out = {}
    for _, w in ipairs(tokens(S.Group.shortName(recipe.name))) do
        if not GRADE[w] and not STOP[w] then out[#out + 1] = w end
    end
    return out
end

local function slotWords(recipe)
    local hay = ((recipe.category or "") .. " " .. (recipe.name or "")):lower()
    local out = {}
    for _, slot in ipairs(SLOTS) do
        if hay:find(slot.key, 1, true) or (slot.key == "two-handed" and hay:find("2h", 1, true)) then
            for _, w in ipairs(slot.words) do out[w] = true end
        end
    end
    return out
end

-- Chat shorthand for stat words. Anything else must be an exact word or a prefix of at least 4 letters.
local ABBR = { str = "strength", agi = "agility", int = "intellect", spi = "spirit", res = "resistance",
               defl = "deflect", hp = "health", stam = "stamina" }

local function hit(word, toks)
    for _, t in ipairs(toks) do
        if t == word or ABBR[t] == word or (#t >= 4 and #t < #word and word:sub(1, #t) == t) then return true end
    end
    return false
end

-- Word lists per recipe never change while the game runs, so work them out once.
local memo = setmetatable({}, { __mode = "k" })
local function facts(r)
    local f = memo[r]
    if not f then
        f = { name = (r.name or ""):lower(), tail = S.Group.shortName(r.name or ""):lower(), words = tailWords(r), slots = slotWords(r) }
        memo[r] = f
    end
    return f
end

-- Which of the owner enchants does this message ask for? Best first, at most 3.
function S.Match.wants(text, recipes)
    local out = {}
    if type(text) ~= "string" or type(recipes) ~= "table" then return out end
    local low = text:lower()
    local toks = tokens(text)
    local present = {}
    for _, t in ipairs(toks) do present[t] = true end
    for _, r in ipairs(recipes) do
        local score = 0
        local fx = facts(r)
        local name, tail, words = fx.name, fx.tail, fx.words
        local hits = 0
        for _, w in ipairs(words) do if hit(w, toks) then hits = hits + 1 end end
        local slotHit = false
        for w in pairs(fx.slots) do if present[w] then slotHit = true end end
        if name ~= "" and low:find(name, 1, true) then score = 100
        elseif tail ~= "" and low:find(tail, 1, true) then score = 95
        elseif #words > 0 and hits == #words then score = 85 + (slotHit and 10 or 0)
        elseif hits > 0 then score = 40 + (slotHit and 30 or 0)
        elseif slotHit then score = 30 end
        if score >= 30 then out[#out + 1] = { recipe = r, score = score } end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.recipe.name or "") < (b.recipe.name or "")
    end)
    if #out > 0 and out[1].score >= 85 then
        local strong = {}
        for _, m in ipairs(out) do if m.score >= 85 then strong[#strong + 1] = m end end
        out = strong
    end
    while #out > 3 do out[#out] = nil end
    return out
end
