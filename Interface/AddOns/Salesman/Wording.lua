local _, S = ...
S.Wording = {}

-- Replaces every occurrence of needle; when wholeWord is set the match must not touch letters or digits.
local function replaceAll(s, needle, repl, wholeWord)
    local out, pos, n = {}, 1, 0
    while needle ~= "" do
        local a, b = s:find(needle, pos, true)
        if not a then break end
        local blocked = false
        if wholeWord then
            local before = a > 1 and s:sub(a - 1, a - 1) or ""
            local after = s:sub(b + 1, b + 1)
            blocked = before:match("%w") ~= nil or after:match("%w") ~= nil
        end
        if blocked then
            out[#out + 1] = s:sub(pos, a)
            pos = a + 1
        else
            out[#out + 1] = s:sub(pos, a - 1) .. repl
            pos = b + 1
            n = n + 1
        end
    end
    out[#out + 1] = s:sub(pos)
    return table.concat(out), n
end

-- Words from an enchant's name that are fine in any ad.
local GENERIC = { enchant = true, enchanting = true, of = true, the = true, to = true, ["and"] = true, an = true, on = true, ["in"] = true }

-- Turns hand-edited ad text back into a template: link, price and mats go back to placeholders.
-- subs = { link=, price= (as shown, e.g. "11s"), mats= }. rebuild(template) must return the text that template
-- would post; the template is only returned when that equals the edited text exactly. Returns template or nil, reason.
function S.Wording.derive(text, subs, rebuild)
    if type(text) ~= "string" or text == "" then return nil, "empty text" end
    if text:find("[{}]") then return nil, "Take the { and } characters out of the text to save it as your wording." end
    local t = text
    if subs.mats and subs.mats ~= "" then t = replaceAll(t, subs.mats, "{mats}") end
    if subs.stats and subs.stats ~= "" then t = replaceAll(t, subs.stats, "{stats}") end
    if subs.link then
        local n
        t, n = replaceAll(t, subs.link, "{link}")
        if n == 0 then return nil, "Keep the enchant link in the text to save your wording." end
    end
    if subs.price then
        local n
        t, n = replaceAll(t, subs.price, "{price}", true)
        if n == 0 then return nil, "Keep the price in the text to save your wording." end
    end
    -- A word from this enchant's own name ("2H", "Lesser") would then appear in every other ad: don't learn it.
    local name = subs.link and subs.link:match("%[(.-)%]")
    if name then
        name = name:gsub("^[^:]*:%s*", "")
        local own = {}
        for w in name:gmatch("%w+") do
            local l = w:lower()
            if not GENERIC[l] and #l >= 2 then own[l] = true end
        end
        local bare = t:gsub("{%a+}", " ")
        for w in bare:gmatch("%w+") do
            if own[w:lower()] then
                return nil, "\"" .. w .. "\" is part of this enchant's name, so other ads would say it too. Your message still went out."
            end
        end
    end
    local built = rebuild(t)
    if built ~= text then return nil, "This wording could not be saved exactly." end
    return t
end
