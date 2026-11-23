-- the three layouts, click-to-cast, combat safety, look settings
priest()
AURAS.player = { "Divine Spirit" }
local ns = boot({ classes = { PRIEST = { enabled = { SPIRIT = true, SHADOWFORM = true } } } })
local db = MissingBuffWarningDB
local box = MissingBuffWarningFrame

section("list layout")
check(boxVisible(), "box shown")
eq(cell("hdr"):GetText(), "Missing buffs (3)", "header count")
check(shown("grp:SELF") and shown("grp:GROUP") and shown("grp:OPTIONAL"), "three group headers")
check(cell("grp:SELF").label:GetText():find("Self") ~= nil, "self header text")
check(shown("row:INNERFIRE") and shown("row:FORTITUDE") and shown("row:SHADOWFORM"), "rows shown")
check(not shown("row:SPIRIT"), "buff that is up has no row")
eq(cell("row:INNERFIRE").name:GetText(), "Inner Fire", "row name")
eq(cell("row:INNERFIRE").icon._w, 16, "icon 16px")
check(cell("row:INNERFIRE").edge:IsShown(), "red edge on")
local b = cell("row:INNERFIRE").cast
check(b ~= nil and b._secure, "secure cast button")
eq(b:GetAttribute("type"), "spell"); eq(b:GetAttribute("spell"), "Inner Fire"); eq(b:GetAttribute("unit"), "player")
check(b:IsMouseEnabled(), "locked: button takes clicks")
check(#b._clicks == 2, "registered for up and down")

section("collapse")
cell("grp:GROUP"):Click()
check(not shown("row:FORTITUDE"), "group collapsed hides rows")
check(shown("grp:GROUP"), "header stays")
eq(db.collapsed.GROUP, true, "saved")
cell("grp:GROUP"):Click()
check(shown("row:FORTITUDE"), "expanded again")
cell("hdr"):Click()
check(not shown("grp:SELF") and not shown("row:INNERFIRE"), "whole list collapsed")
check(shown("hdr"), "main header still there")
cell("hdr"):Click()
check(shown("row:INNERFIRE"), "list open")

section("who is missing")
party({ { "Ann" }, { "Bob", "Power Word: Fortitude" } })
AURAS.player = { "Divine Spirit", "Power Word: Fortitude" }
refresh()
check(shown("row:FORTITUDE"), "fort listed for Ann")
eq(cell("row:FORTITUDE").count:GetText(), "2/3", "have/total")
check(shown("who:FORTITUDE:party1"), "Ann line nested")
eq(cell("who:FORTITUDE:party1").name:GetText(), "Ann")
eq(cell("who:FORTITUDE:party1").cast:GetAttribute("unit"), "party1", "click Ann casts on Ann")
eq(cell("row:FORTITUDE").cast:GetAttribute("unit"), "party1", "I have it: row casts on first missing")
check(not shown("who:FORTITUDE:party2"), "Bob has it")
db.showWho = false; refresh()
check(not shown("row:FORTITUDE"), "show-who off: fort hidden (I have it)")
db.showWho = true; refresh()
eq(errorsPrinted(), 0, "no errors")

section("combat safety")
AURAS.player = { "Divine Spirit" }
party({})
refresh()
check(shown("row:INNERFIRE"), "pre-combat")
enterCombat()
AURAS.player = { "Divine Spirit", "Inner Fire" }
refresh()
eq(errorsPrinted(), 0, "no blocked action in combat")
check(shown("row:INNERFIRE"), "row not hidden in combat (protected)")
check(cell("row:INNERFIRE")._alpha < 1, "but dimmed")
eq(cell("hdr"):GetText(), "Missing buffs (2)", "count updates in combat")
AURAS.player = { "Inner Fire" }   -- Divine Spirit drops mid-fight; it had no row
refresh()
check((box.footer:GetText() or ""):find("Divine Spirit") ~= nil, "new loss listed in footer")
cell("grp:GROUP"):Click()
check(shown("row:FORTITUDE"), "collapse ignored in combat")
eq(errorsPrinted(), 0, "no errors in combat")
AURAS.player = { "Inner Fire", "Divine Spirit" }
leaveCombat()
check(not shown("row:INNERFIRE"), "after combat: reflowed")
eq(box.footer:GetText() or "", "", "footer cleared")
eq(cell("row:FORTITUDE")._alpha, 1, "alpha back")

section("strip layout")
party({ { "Ann" } })
AURAS.player = { "Divine Spirit" }
db.layout = "strip"; refresh()
check(not shown("row:INNERFIRE") and not shown("hdr"), "list frames hidden")
check(shown("ico:INNERFIRE") and shown("ico:FORTITUDE") and shown("ico:SHADOWFORM"), "icons shown")
check(shown("div:1") and shown("div:2"), "two dividers between three groups")
check(not shown("div:3"), "no extra divider")
eq(cell("ico:FORTITUDE").badge:GetText(), "1", "badge: one other person missing it")
check(not cell("ico:INNERFIRE").badge:IsShown() or (cell("ico:INNERFIRE").badge:GetText() or "") == "", "no badge on self buff")
check(cell("ico:SHADOWFORM").icon._alpha < 1, "optional dimmed")
eq(cell("ico:FORTITUDE").cast:GetAttribute("spell"), "Power Word: Fortitude")
cell("ico:FORTITUDE").cast._scripts.OnEnter(cell("ico:FORTITUDE").cast)
local tip = table.concat(GameTooltip._lines, "|")
check(tip:find("Power Word: Fortitude") and tip:find("Ann"), "tooltip shows name and who: " .. tip)
party({})

section("panels layout")
db.layout = "panels"; refresh()
check(not shown("ico:INNERFIRE") and not shown("div:1"), "strip hidden")
check(shown("pan:INNERFIRE"), "big panel")
check(cell("pan:INNERFIRE").body:GetText():find("Your Inner Fire is missing") ~= nil, "old text")
eq(cell("pan:INNERFIRE").cast:GetAttribute("spell"), "Inner Fire")
db.layout = "list"; refresh()
check(not shown("pan:INNERFIRE"), "panels hidden on switch")

section("nothing missing")
AURAS.player = { "Inner Fire", "Power Word: Fortitude", "Divine Spirit", "Shadowform" }
refresh()
check(not boxVisible(), "hidden")
db.whenNone = "fade"; refresh()
check(boxVisible() and box._alpha < 0.5, "faded")
db.whenNone = "hide"; refresh()
enterCombat()
AURAS.player = { "Power Word: Fortitude", "Divine Spirit", "Shadowform" }  -- Inner Fire drops mid-fight
refresh()
eq(errorsPrinted(), 0, "no blocked action")
check(boxVisible() and (box.footer:GetText() or ""):find("Inner Fire") ~= nil, "loss in combat shown though box was empty")
leaveCombat()
check(shown("row:INNERFIRE"), "real row after combat")

section("only in group / combat off")
AURAS.player = { "Divine Spirit" }
db.onlyInGroup = true; refresh()
check(not boxVisible(), "solo hidden")
db.onlyInGroup = false; refresh()
check(boxVisible(), "shown")
db.showInCombat = false
enterCombat()
check(not boxVisible(), "hidden as combat starts (before lockdown)")
refresh()
eq(errorsPrinted(), 0, "no errors")
leaveCombat()
check(boxVisible(), "back after combat")
db.showInCombat = true

section("look settings")
db.iconSize = 24; db.fontSize = 14; db.redEdge = false; db.showBg = false; db.showBorder = false
db.headerColor = "blue"
refresh()
eq(cell("row:INNERFIRE").icon._w, 24, "icon size")
eq(select(2, cell("row:INNERFIRE").name:GetFont()), 14, "font size")
check(not cell("row:INNERFIRE").edge:IsShown(), "red edge off")
check(not box.bg:IsShown(), "background off")
check(not box.border:IsShown(), "border off")
local hc = cell("grp:SELF").label._tcolor
check(hc and hc[3] > hc[1], "blue header colour")
db.showBg = true; db.bgAlpha = 0.3; db.showBorder = true; refresh()
check(box.bg:IsShown() and box.bg._alpha == 0.3, "bg opacity")
check(box.border:IsShown(), "border on")
db.iconSize = 16; db.fontSize = 12; db.redEdge = true; db.headerColor = "gold"

section("grow up")
db.growUp = true; refresh()
local p = cell("row:INNERFIRE")._points[1]
check(p and p[1]:find("BOTTOM") ~= nil, "rows anchored from bottom when growing up")
db.growUp = false; refresh()
p = cell("row:INNERFIRE")._points[1]
check(p and p[1]:find("TOP") ~= nil, "rows from top when growing down")

section("unlock")
ns.SetLocked(false)
check(not cell("row:INNERFIRE").cast:IsMouseEnabled(), "unlocked: clicks go to drag")
check(box.bg:IsShown() and box.hint:IsShown(), "unlock hint")
ns.SetLocked(true)
check(cell("row:INNERFIRE").cast:IsMouseEnabled(), "locked again")

section("passive manual buff")
FAKE.learn("Touch of the Grave", 5227); KNOWN["Touch of the Grave"].passive = true
ns.ClassConfig("PRIEST").manual[1] = { input = "Touch of the Grave", enabled = true }
refresh()
check(shown("row:M:touch of the grave"), "row shown")
eq(cell("row:M:touch of the grave").cast, nil, "no cast button for passive")
eq(errorsPrinted(), 0, "no errors at end")
