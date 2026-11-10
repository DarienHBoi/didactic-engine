local _, S = ...
S.Recipes = {}
S.Recipes.enchantingName = nil -- localized profession name, set in game

function S.Recipes.isEnchanting(prof)
    if type(prof) ~= "table" then return false end
    if prof.professionID == 333 then return true end
    return S.Recipes.enchantingName ~= nil and prof.professionName == S.Recipes.enchantingName
end

-- Recipe links read "[Tailoring: Linen Bag]": the profession name is in the link text.
function S.Recipes.professionFromLink(link)
    if type(link) ~= "string" then return nil end
    return link:match("%[([^%]:]+): ")
end

-- True when a profession (trade) link is for the named profession, e.g. "[Enchanting]".
function S.Recipes.isSkillLink(link, name)
    if type(link) ~= "string" then return false end
    return link:find("[" .. (name or S.Recipes.enchantingName or "Enchanting") .. "]", 1, true) ~= nil
end

function S.Recipes.isEnchantingRecipe(r)
    local fromLink = S.Recipes.professionFromLink(r.link)
    if fromLink then return fromLink == (S.Recipes.enchantingName or "Enchanting") end
    return S.Recipes.isEnchanting(r.profession)
end

-- The profession a recipe belongs to: from its link text ("[Tailoring: Linen Bag]"), else its profession info.
function S.Recipes.professionOf(r)
    if type(r) ~= "table" then return nil end
    local p = S.Recipes.professionFromLink(r.link)
    if p then return p end
    if type(r.profession) == "table" and type(r.profession.professionName) == "string" then return r.profession.professionName end
    return nil
end

-- Sorted unique profession names found in a recipe list.
function S.Recipes.professions(list)
    local seen, out = {}, {}
    for _, r in ipairs(list or {}) do
        local p = S.Recipes.professionOf(r)
        if p and not seen[p] then seen[p] = true; out[#out + 1] = p end
    end
    table.sort(out)
    return out
end

function S.Recipes.scan(api)
    local out = {}
    for i = 1, api.count() do
        local name, kind = api.info(i)
        local link = api.link(i)
        if kind ~= "header" and kind ~= "subheader" and link then
            local reagents = {}
            for j = 1, api.numReagents(i) do
                local rname, _, count, rlink = api.reagent(i, j)
                local id = rlink and tonumber(rlink:match("item:(%d+)"))
                -- An unresolved reagent (item not cached yet) is kept as false so the cost shows unknown.
                reagents[#reagents + 1] = { id or false, count, name = rname, link = rlink }
            end
            out[#out + 1] = { key = link, name = name, link = link, reagents = reagents,
                              category = api.category and api.category(i) or nil,
                              icon = api.icon and api.icon(i) or nil,
                              desc = api.desc and type(api.desc(i)) == "string" and api.desc(i):sub(1, 300) or nil,
                              resultLink = api.resultLink and api.resultLink(i) or nil,
                              stats = api.desc and S.Stats.parse(api.desc(i)) or nil,
                              profession = api.profession and api.profession(i) or nil }
        end
    end
    if #out == 0 then return nil end
    return out
end

-- Merges a scan into the cache so a filtered or collapsed profession list never drops recipes.
function S.Recipes.refresh(api, keep, prune)
    local list = S.Recipes.scan(api)
    if list and keep then
        local kept = {}
        for _, r in ipairs(list) do
            if keep(r) then kept[#kept + 1] = r end
        end
        list = #kept > 0 and kept or nil
    end
    if not list then return nil end
    -- Drop old or malformed entries without a key, then merge by key (last scan row wins).
    -- With prune, a complete scan replaces the cache so forgotten recipes disappear.
    local cache, at = {}, {}
    -- With prune, only the scanned professions are replaced; other professions stay as they were.
    local scanned = {}
    for _, r in ipairs(list) do scanned[S.Recipes.professionOf(r) or false] = true end
    for _, r in ipairs(S.DB.char.recipes) do
        local mine = prune and (scanned[S.Recipes.professionOf(r) or false] or S.Recipes.professionOf(r) == nil)
        if not mine and type(r) == "table" and r.key then
            cache[#cache + 1] = r
            at[r.key] = #cache
        end
    end
    for _, r in ipairs(list) do
        if at[r.key] then
            cache[at[r.key]] = r
        else
            cache[#cache + 1] = r
            at[r.key] = #cache
        end
    end
    S.DB.char.recipes = cache
    S.DB.char.scannedAt = time and time() or 0
    return list
end
