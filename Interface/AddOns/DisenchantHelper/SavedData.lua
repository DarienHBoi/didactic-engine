-- Shared guard for experimental learning/statistics storage. Unknown schemas
-- stay untouched; known-format repairs require a recoverable snapshot first.
local _, ns = ...
local SavedData = {}
ns.SavedData = SavedData

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[Copy(key, seen)] = Copy(child, seen)
    end
    return copy
end

-- Returns the writable store, or nil when loading it would risk existing data.
function SavedData.Prepare(db, key, healthy, create)
    local current = db[key]
    if current == nil then
        current = create()
        db[key] = current
        return current
    end
    if type(current) == "table" and current.v ~= nil and current.v ~= 1 then
        return nil
    end
    if type(current) == "table" and current.v == 1 and healthy(current) then
        return current
    end

    local backupKey = key .. "Backup"
    -- Never replace an earlier recovery snapshot to make room for a new one.
    -- If another repair is needed, stop this module until the data is reviewed.
    if db[backupKey] ~= nil then return nil end
    db[backupKey] = Copy(current)
    if type(current) ~= "table" then
        current = create()
        db[key] = current
    end
    current.v = 1
    return current
end
