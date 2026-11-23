local _, S = ...
S.Message = { MAX = 255 }

local CRAFTER = {
    Enchanting = "ENCHANTER", Leatherworking = "LEATHERWORKER", Tailoring = "TAILOR", Blacksmithing = "BLACKSMITH",
    Alchemy = "ALCHEMIST", Engineering = "ENGINEER", Cooking = "COOK", Jewelcrafting = "JEWELCRAFTER",
    Inscription = "SCRIBE", ["First Aid"] = "FIRST AID",
}

-- The advert word for someone with this profession ("Leatherworking" -> "LEATHERWORKER").
function S.Message.crafter(profession)
    if type(profession) ~= "string" or profession == "" then return "CRAFTER" end
    return CRAFTER[profession] or profession:upper()
end

-- Advert for the profession itself: only {link} is required; {crafter} names the profession's crafter.
function S.Message.buildSkill(template, link, profession)
    if not template:find("{link}", 1, true) then return nil, "template needs {link}" end
    if link == nil or link == "" then return nil, "skill link missing (open your profession window once)" end
    local escaped = template:gsub("|", "||")
    local word = S.Message.crafter(profession)
    local text = escaped:gsub("{(%a+)}", function(k)
        if k == "link" then return link end
        if k == "crafter" then return word end
    end)
    if #text > S.Message.MAX then return nil, "message longer than 255 characters" end
    return text
end

-- Checks hand-edited text before it is posted: trimmed, not empty, at most 255 characters.
function S.Message.validate(text)
    if type(text) ~= "string" then return nil, "message empty" end
    text = text:match("^%s*(.-)%s*$")
    if text == "" then return nil, "message empty" end
    if #text > S.Message.MAX then return nil, "message longer than 255 characters" end
    return text
end

function S.Message.build(template, link, copper, mats, stats)
    if not template:find("{link}", 1, true) then return nil, "template needs {link}" end
    if not template:find("{price}", 1, true) then return nil, "template needs {price}" end
    if link == nil or link == "" then return nil, "link missing" end
    if copper == nil or copper <= 0 then return nil, "price unknown" end
    if template:find("{mats}", 1, true) and (mats == nil or mats == "") then return nil, "mats missing" end
    local price = S.Money.format(copper)
    if stats == nil or stats == "" then
        -- No stats known: the placeholder and one neighbouring space disappear so the line reads cleanly.
        template = template:gsub(" {stats}", ""):gsub("{stats} ", ""):gsub("{stats}", "")
    end
    -- Single pass, so text inside the link is never re-substituted. Bare pipes in the template are escaped.
    local escaped = template:gsub("|", "||")
    local text = escaped:gsub("{(%a+)}", function(k)
        if k == "link" then return link end
        if k == "price" then return price end
        if k == "mats" then return mats end
        if k == "stats" then return stats end
    end)
    if #text > S.Message.MAX then return nil, "message longer than 255 characters" end
    return text
end
