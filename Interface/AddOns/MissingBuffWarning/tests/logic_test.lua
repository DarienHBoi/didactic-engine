-- settings, migration, grouping, party checks, visibility rules
priest()

section("migration")
local old = { scale = 0.8375, x = 1000, y = 800, locked = true,
    classes = { PRIEST = { enabled = { SPIRIT = true, SHADOWPROT = false }, manual = {} } },
    probe = { "junk" }, minimap = { angle = 249, hidden = false } }
AURAS.player = { "Inner Fire", "Power Word: Fortitude", "Divine Spirit" }
local ns = boot(old)
local db = MissingBuffWarningDB
eq(db.version, 2, "version")
eq(db.layout, "list", "default layout A")
eq(db.scale, 0.8375, "old scale kept")
eq(db.x, 1000, "old x kept"); eq(db.y, 800, "old y kept")
eq(db.locked, true, "lock kept")
eq(db.probe, nil, "old probe junk removed")
eq(db.minimap.angle, 249, "minimap kept")
eq(db.classes.PRIEST.enabled.SPIRIT, true, "enabled buffs kept")
eq(db.iconSize, 16, "icon size default"); eq(db.fontSize, 12, "font default")
eq(db.showWho, true, "show who default"); eq(db.showInCombat, true, "combat default")
eq(db.whenNone, "hide", "nothing missing: hide"); eq(db.growUp, false, "grow down")
eq(errorsPrinted(), 0, "no errors")

section("fresh")
ns = boot(nil)
db = MissingBuffWarningDB
eq(db.version, 2, "version"); eq(db.layout, "list", "layout"); eq(db.scale, 1, "scale 1")

section("groups")
local tracked = ns.BuildTracked("PRIEST", ns.ResolveSpell)
local byKey = {}
for _, t in ipairs(tracked) do byKey[t.key] = t end
eq(byKey.INNERFIRE.group, "SELF", "inner fire self")
eq(byKey.FORTITUDE.group, "GROUP", "fort group")
check(byKey.SPIRIT == nil, "spirit off by default")
ns.ClassConfig("PRIEST").enabled.SHADOWFORM = true
ns.ClassConfig("PRIEST").enabled.SPIRIT = true
tracked = ns.BuildTracked("PRIEST", ns.ResolveSpell)
byKey = {}
for _, t in ipairs(tracked) do byKey[t.key] = t end
eq(byKey.SHADOWFORM.group, "OPTIONAL", "shadowform optional")
eq(byKey.SPIRIT.group, "GROUP", "spirit group")
ns.ClassConfig("PRIEST").groups.INNERFIRE = "OPTIONAL"
eq(ns.BuildTracked("PRIEST", ns.ResolveSpell)[1].group, "OPTIONAL", "override kept")
ns.ClassConfig("PRIEST").groups.INNERFIRE = nil
ns.ClassConfig("PRIEST").manual[1] = { input = "Touch of Weakness", enabled = true }
FAKE.learn("Touch of Weakness", 2652)
tracked = ns.BuildTracked("PRIEST", ns.ResolveSpell)
eq(tracked[#tracked].key, "M:touch of weakness", "manual key")
eq(tracked[#tracked].group, "SELF", "manual default self")
ns.ClassConfig("PRIEST").manual = {}

section("view solo")
tracked = ns.BuildTracked("PRIEST", ns.ResolveSpell)
local view = ns.BuildView(tracked, { ["Divine Spirit"] = true }, nil)
eq(view.count, 3, "inner fire, fort, shadowform missing")
eq(#view.groups, 3, "three groups")
eq(view.groups[1].id, "SELF"); eq(view.groups[2].id, "GROUP"); eq(view.groups[3].id, "OPTIONAL")
eq(view.groups[2].items[1].label, "Power Word: Fortitude", "fort in group")
eq(view.groups[2].items[1].playerMissing, true, "player missing fort")
view = ns.BuildView(tracked, { ["Inner Fire"] = true, ["Power Word: Fortitude"] = true,
    ["Divine Spirit"] = true, ["Shadowform"] = true }, nil)
eq(view.count, 0, "nothing missing"); eq(#view.groups, 0, "no groups")
view = ns.BuildView(tracked, { ["Prayer of Fortitude"] = true, ["Inner Fire"] = true,
    ["Divine Spirit"] = true, ["Shadowform"] = true }, nil)
eq(view.count, 0, "group version counts")

section("party scan")
party({ { "Ann", "Divine Spirit" }, { "Bob", "Prayer of Fortitude", "Divine Spirit" } })
AURAS.player = {}
local p = ns.ScanParty(tracked)
eq(p.FORTITUDE.total, 3, "me + 2"); eq(p.FORTITUDE.have, 1, "only Bob has fort (me not counted yet)")
AURAS.player = { "Inner Fire", "Power Word: Fortitude", "Divine Spirit", "Shadowform" }
p = ns.ScanParty(tracked)
eq(p.FORTITUDE.have, 2, "me and Bob")
eq(#p.FORTITUDE.who, 1, "one missing"); eq(p.FORTITUDE.who[1].name, "Ann"); eq(p.FORTITUDE.who[1].unit, "party1")
check(p.INNERFIRE == nil, "self buffs are not checked on others")
view = ns.BuildView(tracked, { ["Inner Fire"] = true, ["Power Word: Fortitude"] = true,
    ["Divine Spirit"] = true, ["Shadowform"] = true }, p)
eq(view.count, 1, "fort listed because Ann misses it")
local it = view.groups[1].items[1]
eq(it.key, "FORTITUDE"); eq(it.playerMissing, false, "I have it"); eq(it.have, 2); eq(it.total, 3)
eq(it.who[1].name, "Ann")
MissingBuffWarningDB.showWho = false
view = ns.BuildView(tracked, { ["Inner Fire"] = true, ["Power Word: Fortitude"] = true,
    ["Divine Spirit"] = true, ["Shadowform"] = true }, p)
eq(view.count, 0, "party ignored when show-who is off")
MissingBuffWarningDB.showWho = true

section("party: dead/offline skipped, raid units")
UNITS.party2.offline = true
p = ns.ScanParty(tracked)
eq(p.FORTITUDE.total, 2, "offline Bob not counted")
UNITS.party2.offline = nil
UNITS.party1.dead = true
p = ns.ScanParty(tracked)
eq(p.FORTITUDE.total, 2, "dead Ann not counted"); eq(#p.FORTITUDE.who, 0)
UNITS.party1.dead = nil
party({}); UNITS.raid1 = { name = "Me", isPlayer = true }; UNITS.raid2 = { name = "Cy" }; AURAS.raid2 = {}
INGROUP = "raid"
p = ns.ScanParty(tracked)
eq(p.FORTITUDE.total, 2, "raid: me + Cy (raid1 is me)"); eq(p.FORTITUDE.who[1].name, "Cy")
UNITS.raid1, UNITS.raid2, INGROUP = nil, nil, false

section("party: combat keeps last known")
party({ { "Ann" } })
p = ns.ScanParty(tracked)
eq(#p.FORTITUDE.who, 1, "Ann missing")
COMBAT = true
AURAS.party1 = { "Power Word: Fortitude" }
p = ns.ScanParty(tracked)
eq(#p.FORTITUDE.who, 1, "in combat: last known state kept")
COMBAT = false
p = ns.ScanParty(tracked)
eq(#p.FORTITUDE.who, 0, "after combat: updated")
AURAS.party1 = { "Something" }
SECRET.party1 = true
p = ns.ScanParty(tracked)
eq(#p.FORTITUDE.who, 0, "hidden names: member keeps last known (had it)")
SECRET.party1 = "throw"
p = ns.ScanParty(tracked)
eq(#p.FORTITUDE.who, 0, "aura read throws: kept")
SECRET.party1 = nil
party({})

section("visibility")
db = MissingBuffWarningDB
local some, none = { count = 2 }, { count = 0 }
eq(ns.Visibility(some), "show", "missing -> show")
eq(ns.Visibility(none), "hide", "nothing -> hide")
db.whenNone = "fade"; eq(ns.Visibility(none), "fade", "nothing -> fade"); db.whenNone = "hide"
db.onlyInGroup = true; eq(ns.Visibility(some), "hide", "solo + only in group");
INGROUP = true; eq(ns.Visibility(some), "show", "in group"); INGROUP = false; db.onlyInGroup = false
COMBAT = true; db.showInCombat = false; eq(ns.Visibility(some), "hide", "combat off")
db.showInCombat = true; eq(ns.Visibility(some), "show", "combat on"); COMBAT = false
UNITS.player.taxi = true; eq(ns.Visibility(some), "hide", "taxi"); UNITS.player.taxi = nil
UNITS.player.dead = true; eq(ns.Visibility(some), "hide", "dead"); UNITS.player.dead = nil
db.locked = false; eq(ns.Visibility(none), "show", "unlocked preview always shows"); db.locked = true
eq(errorsPrinted(), 0, "no errors")
