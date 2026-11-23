-- AscendXP: one shared XP track, independent rested and quest projections.
-- Rested XP has blue priority. The quest projection uses the remaining gold
-- tail (if any) and an endpoint marker so that it remains visible even when
-- the rested fill entirely covers the same region. Neither projection is
-- summed with the other: both start at the player's CURRENT XP.
local addonName, addon = ...
local min, max = math.min, math.max
local Projection = {}

function Projection.Compute(xp, maximum, rested, quest, width, showRested, showQuest)
    xp = max(0, tonumber(xp) or 0)
    maximum = max(0, tonumber(maximum) or 0)
    rested = max(0, tonumber(rested) or 0)
    quest = max(0, tonumber(quest) or 0)
    width = max(0, tonumber(width) or 0)

    local result = {
        progress = 0, restedStart = 0, restedWidth = 0,
        questStart = 0, questWidth = 0,
        markerX = 0, showMarker = false,
    }
    if maximum == 0 or width == 0 then return result end

    local progress = width * min(1, xp / maximum)
    local capacity = max(0, maximum - xp)
    local restedEnd = progress
    if showRested and rested > 0 then
        restedEnd = min(width, progress + width * min(rested, capacity) / maximum)
    end
    local questEnd = progress
    if showQuest and quest > 0 then
        questEnd = min(width, progress + width * min(quest, capacity) / maximum)
    end

    result.progress = progress
    result.restedStart = progress
    result.restedWidth = max(0, restedEnd - progress)
    result.questStart = restedEnd
    result.questWidth = max(0, questEnd - restedEnd)
    -- The 2px gold line still marks quest XP if blue rested XP covers it.
    -- Clamp the line inside the track at the far right edge.
    result.markerX = min(max(1, width - 1), questEnd)
    result.showMarker = showQuest and quest > 0 and capacity > 0 and questEnd > progress
    return result
end

addon.Projection = Projection
