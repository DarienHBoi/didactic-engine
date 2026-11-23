local addon, ns = ...
local requiredContract = 4

local function compatible(provider)
    if type(provider) ~= 'table' or type(provider.RequireContract) ~= 'function' then return false end
    local ok, accepted = pcall(provider.RequireContract, requiredContract)
    if not ok or not accepted then return false end
    return provider.flavor and provider.flavor.name == 'Forever'
        and provider.Quest and type(provider.Quest.Get) == 'function' and type(provider.Quest.GetAllIds) == 'function'
        and provider.Npc and type(provider.Npc.Get) == 'function'
        and provider.Object and type(provider.Object.Get) == 'function'
        and provider.Item and type(provider.Item.Get) == 'function'
        and provider.Support and type(provider.Support.Get) == 'function'
        and provider.Enum and type(provider.Enum.raceMaskById) == 'table'
end

local function versionParts(version)
    if type(version) ~= 'string' then return end
    local major, minor, patch, suffix = version:match('^v?(%d+)%.(%d+)%.(%d+)(.*)$')
    if not major then return end
    return { tonumber(major), tonumber(minor), tonumber(patch), suffix == '' and 1 or 0 }
end

local function atLeast(version, minimum)
    local left, right = versionParts(version), versionParts(minimum)
    if not left or not right then return false end
    for i = 1, 4 do
        if left[i] ~= right[i] then return left[i] > right[i] end
    end
    return true
end

function ns.ResolveDatabase()
    if ns.database then return ns.database end
    local getter = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local external = _G.LibQuestieDB
    local version = getter and getter('QuestieDB', 'Version')
    if compatible(external) and atLeast(version, ns.bundledDatabaseVersion) then
        ns.database = external
        ns.databaseStatus = 'QuestieDB ' .. version .. ' (installed)'
    else
        local ok, provider = pcall(ns.LoadBundledDatabase)
        if not ok then return nil, 'Bundled database could not load: ' .. tostring(provider) end
        if not compatible(provider) then return nil, 'Bundled database is incompatible with this client.' end
        ns.database = provider
        ns.databaseStatus = 'Bundled database ' .. ns.bundledDatabaseVersion
    end
    -- Release the initializer and its unused code once a provider has been selected.
    ns.LoadBundledDatabase = nil
    return ns.database
end
