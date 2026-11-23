-- Waypoints through the game's own pin and in-world marker (C_Map.SetUserWaypoint + C_SuperTrack), so there is no
-- arrow of ours to draw. Two rules: we never clear or replace a waypoint the player placed (once they set their own,
-- we wait until the step changes), and for an objective whose location we only have from the Classic baseline, we
-- super-track the quest itself, which shows Blizzard's objective area for the current build.
local _, ns = ...

local WP = { owned = nil, yieldedFor = nil, setting = false }
local RETRACK_YARDS = 60   -- yards from a waypoint you reached before it's tracked again
ns.Waypoint = WP

local function same(a, b)
  return a and b and a.map == b.map and math.abs((a.x or 0) - (b.x or 0)) < 0.05 and math.abs((a.y or 0) - (b.y or 0)) < 0.05
end

local function current()
  if not (C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then return nil end
  local p = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
  if not p then return nil end
  local x, y = ns.clean(p.position and p.position.x), ns.clean(p.position and p.position.y)
  return { map = ns.clean(p.uiMapID), x = x and x * 100, y = y and y * 100 }
end

--- clear our own waypoint (and only ours)
function WP.Clear()
  if WP.paused then return end   -- (/bofg mark test holds the waypoint)
  if WP.owned and WP.owned.map and same(current(), WP.owned) then
    WP.setting = true
    C_Map.ClearUserWaypoint()
    WP.setting = false
  end
  WP.owned = nil
end

--- point the player at target = { key, map, x, y, quest, hybrid }
function WP.Set(target)
  if WP.paused then return end
  if not target or (ns.settings and ns.settings.waypoint == 'off') then return WP.Clear() end
  if WP.yieldedFor and WP.yieldedFor == target.key then return end   -- the player chose their own for this step
  WP.yieldedFor = nil
  WP.aim = target.key   -- (two steps at one spot keep one waypoint, and owned keeps the first's key)
  if target.hybrid and target.quest and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID
      and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(target.quest) then
    if WP.owned and WP.owned.quest == target.quest then return end
    WP.Clear()
    C_SuperTrack.SetSuperTrackedQuestID(target.quest)
    WP.owned = { key = target.key, quest = target.quest }
    return
  end
  if not (target.map and target.x) then return WP.Clear() end
  local want = { key = target.key, map = target.map, x = target.x, y = target.y }
  if same(WP.owned, want) and same(current(), want) then
    -- (reached, then left before the step was done: the game stops tracking a waypoint you reach and keeps its pin,
    -- so the marker and its distance were gone for the rest of the step. Tracked again 60 yd off, unless you track
    -- something yourself since; the RestedXP arrow study, Nov 9)
    if WP.arrived == target.key and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint
        and not (C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint())
        and not ((ns.clean(C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()) or 0) > 0) then
      local d = ns.Geo and ns.Geo.YardsTo({ target.map, target.x, target.y })
      if d and d > RETRACK_YARDS then
        WP.arrived = nil
        WP.setting = true
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        WP.setting = false
      end
    end
    return
  end
  if not (C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(target.map)) then return WP.Clear() end
  WP.setting = true
  local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(target.map, target.x / 100, target.y / 100))
  if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  WP.setting = false
  WP.owned = ok and want or nil
end

--- is the game's waypoint on this step, as ours? (the Waymark hangs from it: never from the player's own, a quest's
--- objective area, or a point on the way)
function WP.Aimed(key)
  local o = WP.owned
  return (o and key and WP.aim == key and not o.quest and same(current(), o)) and true or false
end

--- the world map opened at a zone (FB-035, Oct 22: a creator asked to see the step on the map in one click). The
--- game's own OpenWorldMap (Blizzard_WorldMap: ShowUIPanel, then SetMapID), as a player's M and a zone pick would do;
--- never in a fight (a panel opened by an addon in combat risks taint), and the map frame itself is never changed
function WP.ShowOnMap(map)
  local L = ns.L
  if not map then ns.say(L.mapNone) return false end
  if InCombatLockdown and InCombatLockdown() then ns.say(L.mapCombat) return false end
  if not OpenWorldMap and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, 'Blizzard_WorldMap') end
  local open = OpenWorldMap or (C_Map and C_Map.OpenWorldMap)
  local ok = open and pcall(open, map)
  if not ok then ns.say(L.mapFailed) end
  return ok and true or false
end

--- yards to the waypoint, as the game measures it
function WP.Distance()
  local d = C_Navigation and C_Navigation.GetDistance and ns.clean(C_Navigation.GetDistance())
  return d
end

ns.On('USER_WAYPOINT_UPDATED', function()
  if WP.setting or not WP.owned or WP.owned.quest then return end
  if not same(current(), WP.owned) then
    -- the player placed (or cleared) a waypoint of their own: leave it alone until the step changes
    WP.yieldedFor = WP.owned.key
    WP.owned = nil
  end
end)

-- you reached the waypoint: the game stops tracking it (Blizzard_QuestNavigation, SuperTrackedFrame); remember for which
-- step, so walking off again tracks it again (WP.Set)
ns.On('NAVIGATION_DESTINATION_REACHED', function()
  if WP.owned and not WP.owned.quest then WP.arrived = WP.owned.key end
end)
