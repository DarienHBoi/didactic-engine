local _, ns = ...

local function read(func, ...)
    if type(func) ~= 'function' then return end
    local ok, value = pcall(func, ...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end

-- Training spell IDs for the three professions used by Forever's current
-- requiredRanks records. Unknown professions/tiers remain undecided.
local training = {
    [164] = {2018, 3100, 3538, 9785},
    [165] = {2108, 3104, 3811, 10662},
    [197] = {3908, 3909, 3910, 12180},
}
local specializations = {
    [164] = {9787, 9788},
    [165] = {10656, 10658, 10660},
    [171] = {28672, 28675, 28677},
    [197] = {26797, 26798, 26801},
    [202] = {20219, 20222},
}

function ns.CreateEligibility(database, completed)
    local skills, ready, knownCache = {}, false, {}
    local api = {}
    local function known(id)
        if knownCache[id] ~= nil then return knownCache[id] end
        local func = C_SpellBook and C_SpellBook.IsSpellKnown or IsSpellKnown
        local value = read(func, id)
        if type(value) == 'boolean' then knownCache[id] = value; return value end
    end
    function api:RefreshSkills()
        skills, ready, knownCache = {}, false, {}
        if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
            local count = read(C_SkillInfo.GetNumSkillLines)
            if type(count) ~= 'number' or count <= 0 then return end
            local complete = true
            for i = 1, count do
                local info = read(C_SkillInfo.GetSkillLineInfo, i)
                if not info then complete = false
                elseif info.isHeader and info.isCollapsed then complete = false
                elseif not info.isHeader and info.skillID then skills[info.skillID] = {points = info.rank} end
            end
            ready = complete
        elseif GetProfessions and GetProfessionInfo then
            local ok, professions = pcall(function() return {GetProfessions()} end)
            if not ok then return end
            for _, index in pairs(professions) do
                local success, _, _, rank, _, _, _, id = pcall(GetProfessionInfo, index)
                if success and id then skills[id] = {points = rank} end
            end
            ready = true
        end
    end
    local function hasSkill(id, points)
        local skill = skills[id]
        if not skill and C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
            local info = read(C_SkillInfo.GetSkillLineInfoByID, id)
            if type(info) == 'table' and not info.isHeader then
                skill = {points = info.rank}; skills[id] = skill
            end
        end
        if not skill then if ready then return false end; return end
        if points and points > 0 then
            if type(skill.points) ~= 'number' or (issecretvalue and issecretvalue(skill.points)) then return end
            return skill.points >= points
        end
        return true
    end
    local function rankKnown(id, rank, exact)
        if hasSkill(id) == false then return false end
        local spells = training[id]
        if not spells or not spells[rank] then return end
        local uncertain = false
        for tier = rank, exact and rank or #spells do
            local value = known(spells[tier])
            if value == true then return true end
            if value == nil then uncertain = true end
        end
        if not uncertain then return false end
    end
    local function rankRequirements(rows)
        local positive, met, uncertain = false, false, false
        for _, pair in ipairs(rows or {}) do
            local id, rank = pair[1], pair[2]
            if type(id) == 'number' and type(rank) == 'number' then
                if rank < 0 then
                    if rankKnown(id, -rank, true) == true then return false end
                elseif rank > 0 then
                    positive = true
                    local value = rankKnown(id, rank, false)
                    if value == true then met = true elseif value == nil then uncertain = true end
                end
            end
        end
        return not positive or met or uncertain
    end
    local function specializationAllowed(id)
        if specializations[id] then
            if hasSkill(id) == false then return false end
            -- A profession ID here means its specialization-choice quests: no spec yet.
            for _, spell in ipairs(specializations[id]) do if known(spell) == true then return false end end
            return true
        end
        -- Only classify documented specialization spell IDs; unknown IDs stay visible.
        for _, group in pairs(specializations) do
            for _, spell in ipairs(group) do if id == spell then return known(id) ~= false end end
        end
        if id == 17039 or id == 17040 or id == 17041 then return known(id) ~= false end
        return true
    end
    local function onQuest(id) return read(C_QuestLog.IsOnQuest, id) end
    local function done(id) return read(completed, id) end
    local function satisfied(id)
        if id < 0 then return onQuest(-id) end
        return done(id)
    end
    function api:Allows(id)
        -- Forever delivers these Collector's Edition pets through the Pet Journal.
        if id == 60860 then return false end
        local get = database.Quest.Get
        local skill = get(id, 'requiredSkill')
        if skill and skill[1] and skill[1] > 0 and hasSkill(skill[1], skill[2]) == false then return false end
        if not rankRequirements(get(id, 'requiredRanks')) then return false end
        local spec = get(id, 'requiredSpecialization') or 0
        if spec > 0 and not specializationAllowed(spec) then return false end
        local parent = get(id, 'parentQuest') or 0
        if parent > 0 and onQuest(parent) == false then return false end
        local any = get(id, 'preQuestSingle')
        if any and #any > 0 then
            local possible = false
            for _, quest in ipairs(any) do if satisfied(quest) ~= false then possible = true; break end end
            if not possible then return false end
        else
            for _, quest in ipairs(get(id, 'preQuestGroup') or {}) do if satisfied(quest) == false then return false end end
        end
        for _, quest in ipairs(get(id, 'exclusiveTo') or {}) do
            if quest > 0 and (done(quest) == true or onQuest(quest) == true) then return false end
        end
        for _, field in ipairs({'nextQuestInChain', 'availableUntilCompleted', 'availableStartingWith', 'disabledByQuest'}) do
            local quest = get(id, field) or 0
            if quest > 0 then
                local active, finished = onQuest(quest), done(quest)
                if field == 'nextQuestInChain' and (active == true or finished == true) then return false end
                if field == 'availableUntilCompleted' and finished == true then return false end
                if field == 'availableStartingWith' and active == false and finished == false then return false end
                if field == 'disabledByQuest' and active == true then return false end
            end
        end
        local level = read(UnitLevel, 'player')
        local maximum, minimum = get(id, 'requiredMaxLevel') or 0, get(id, 'requiredLevel') or 0
        if type(level) == 'number' and ((maximum > 0 and level > maximum) or level < minimum) then return false end
        local spell = get(id, 'requiredSpell') or 0
        if spell > 0 and known(spell) == false then return false end
        for _, field in ipairs({'requiredMinRep', 'requiredMaxRep'}) do
            local pair = get(id, field)
            if pair and pair[1] and pair[1] > 0 and type(pair[2]) == 'number' then
                local faction = read(C_Reputation and C_Reputation.GetFactionDataByID, pair[1])
                local value = faction and faction.currentStanding
                if not (issecretvalue and issecretvalue(value)) and type(value) == 'number' then
                    if field == 'requiredMinRep' and value < pair[2] then return false end
                    if field == 'requiredMaxRep' and value >= pair[2] then return false end
                end
            end
        end
        return true
    end
    return api
end
