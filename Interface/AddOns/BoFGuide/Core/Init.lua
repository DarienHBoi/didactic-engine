-- Bind on Forever Guide: a leveling guide for WoW Forever, with dungeon guides and (as imports) profession guides.
--
-- How it works: route packs (BoFGuide_Horde, BoFGuide_Alliance, or a pasted import) are plain data compiled from
-- our route files. Each step's status comes from the game: completed quests, the quest log and its objectives,
-- level and XP, flight paths known, where your hearth is. So you can start at any level, do things out of order, and
-- a route update never loses your place (steps have stable keys).
--
-- Rules we keep (Forever runs Midnight's addon rules): Blizzard frames and functions are never touched; every value
-- read from the game goes through ns.clean() because Forever can hide values from addons; every event registration
-- and handler runs in pcall and errors are kept (capped) in BoFGuideDB.errors.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.VERSION = '0.9.151'
ns.SCHEMA = 1
BoFGuide = ns   -- one global, for packs (BoFGuide_RegisterPack) and for debugging with /dump

ns.DEFAULTS = {
  waypoint = 'blizzard',     -- blizzard: the game's own map pin and in-world marker as well; off: none
  arrow = true,              -- our own waypoint arrow (Nav/Arrow.lua)
  arrowLocked = false,
  arrowScale = 1,
  panelScale = 1,            -- the Targets and Quest Items panels' size
  arrowText = true,          -- the step's text under the arrow (the window shows it too)
  arrowLook = 'relic',       -- relic: our painted arrow; gold, white, green, blue, purple, red: a plain solid arrow;
                             -- direction: a plain arrow that turns green ahead, yellow to the side, red behind
  hc = 'auto',               -- auto: Hardcore steps when the realm is Hardcore; on; off
  shown = true,
  locked = false,
  collapsed = false,         -- only the header and the current step
  scale = 1,
  width = 340,
  opacity = 0.6,              -- the stone behind the steps (owner, Oct 9: 60% looks best)
  textScale = 1,
  font = 'brand',            -- brand: Cinzel and Inter (Media/Fonts); game: the game's own fonts
  cards = 4,                 -- step cards at once (the current step, then the others here and the ones you carry)
  upcoming = 4,              -- next steps listed under the cards
  items = true,              -- the Quest Items panel: buttons for the quest items the steps on screen need
  targets = true,            -- the Targets panel: a portrait button for each enemy and person the steps name
  marks = false,             -- the Waymark (UI/Marks.lua): off until it has been seen in the real game; /bofg mark on
  markScale = 1,             -- its size
  markLift = 0,              -- pixels higher than it sits by itself
  toasts = true,             -- a short plate when a quest is done or ready to hand in
  minimap = true,            -- the seal on the minimap's edge
  minimapAngle = 215,
  sounds = true,
  -- automation acts only on the route's own quests, never in combat, and holding any modifier key stops it. Off for a
  -- new install (owner, Oct 30): the guide is about the full questing experience; the oath offers it, loudly
  auto = { accept = false, turnin = false, gossip = false, taxi = false },
  readNew = false,           -- leave quests no character here has done yet for you to read (accepts the rest)
  combatFade = true,         -- the window fades back in a fight
  dungeons = true,          -- dungeon runs on your leveling road (off: their stops and the quests done inside go)
  sellGrays = false,        -- sell your gray items when you open a vendor
  dangerMap = true,
  nextMap = true,           -- the guide's next stops, numbered, on the world map         -- elites and rares on the world map
  airTimer = true,          -- Walk on Air's seconds left (Skyborne)
  rareAlert = true,         -- a rare's nameplate named once in chat
  breath = false,           -- the drowning warning: the screen's edges glow red below a fifth of your breath (off by
                            -- default since 0.9.119, the owner: too loud; the Settings page turns it on)
  groupQuests = 'party',     -- optional group quests: 'party' (when you're in one), 'always' or 'never'
  storyOpen = false,         -- quests' stories shown open (else a click on "Story" opens one)
}
-- settings upgrades: 2 = automation on by default (0.5.0; 0.4.x saved it off without the player choosing); 3 = the
-- drowning warning off for everyone once (0.9.119: it was saved on as the old default, not by choice)
local SETTINGS_REV = 3

--- SavedVariables, created or upgraded once the game has loaded them
function ns.InitDB()
  BoFGuideDB = BoFGuideDB or {}
  local db = BoFGuideDB
  db.schema = ns.SCHEMA
  db.settings = db.settings or {}
  local rev = db.settingsRev or (next(db.settings) and 1 or SETTINGS_REV)
  for k, v in pairs(ns.DEFAULTS) do
    if db.settings[k] == nil then db.settings[k] = type(v) == 'table' and CopyTable(v) or v end
  end
  for k, v in pairs(ns.DEFAULTS.auto) do if db.settings.auto[k] == nil then db.settings.auto[k] = v end end
  if rev < 2 then for k in pairs(ns.DEFAULTS.auto) do db.settings.auto[k] = true end end
  if rev < 3 then db.settings.breath = false end
  db.settingsRev = SETTINGS_REV
  db.frames = db.frames or {}
  db.imports = db.imports or {}
  db.seen = db.seen or {}      -- quests finished by any character on this account (read new quests)
  db.errors = db.errors or {}
  BoFGuideCharDB = BoFGuideCharDB or {}
  local c = BoFGuideCharDB
  -- a character deleted and made again with the same name gets this file: it starts fresh (the RestedXP audit, Oct 18:
  -- a new level 1 could open on the old one's level 20 leg, with its skips and its inn)
  local guid = UnitGUID and UnitGUID('player')
  if guid and not (issecretvalue and issecretvalue(guid)) then
    if c.guid and c.guid ~= guid then
      for k in pairs(c) do c[k] = nil end
      ns.freshChar = true
    end
    c.guid = guid
  end
  c.schema = ns.SCHEMA
  for _, k in ipairs({ 'skip', 'unskip', 'done', 'taxi', 'stats', 'kills', 'entered', 'seen', 'cleared', 'dungeons', 'loops', 'loopDir', 'paths' }) do
    c[k] = c[k] or {}
  end
  -- 0.9.106 took every flight point the world map lists as known (Forever marks them all discovered: 38 of 38 on
  -- Teldrassil for a level 12): the list starts over once, and the next flight master's map you open fills it again
  if (c.taxiRev or 0) < 2 then
    c.taxi = {}
    c.taxiRev = 2
  end
  ns.db, ns.cdb, ns.settings = db, c, db.settings
end
