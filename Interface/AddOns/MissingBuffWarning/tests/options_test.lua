-- options panel: all four areas present and wired to the saved settings
priest()
AURAS.player = { "Divine Spirit" }
local ns = boot(nil)
local db = MissingBuffWarningDB

section("open")
SlashCmdList.MISSINGBUFFWARNING("")
local panel = MissingBuffWarningOptions
check(panel and panel:IsShown(), "panel opens with /mbw")
local C = ns.optControls
check(C ~= nil, "controls exposed")

section("layout")
eq(C.layout:GetText(), "Layout: Grouped list")
C.layout:Click(); eq(db.layout, "strip"); eq(C.layout:GetText(), "Layout: Icon strip")
C.layout:Click(); eq(db.layout, "panels"); eq(C.layout:GetText(), "Layout: Big panels")
C.layout:Click(); eq(db.layout, "list")

section("size and spacing")
for _, k in ipairs({ "scale", "iconSize", "spacing", "fontSize" }) do
    check(C[k] and C[k].plus and C[k].minus, k .. " stepper")
end
C.iconSize.plus:Click(); eq(db.iconSize, 18, "icon +2")
C.iconSize.minus:Click(); eq(db.iconSize, 16, "icon -2")
for _ = 1, 20 do C.iconSize.minus:Click() end
eq(db.iconSize, 10, "icon min 10")
db.iconSize = 16
C.fontSize.plus:Click(); eq(db.fontSize, 13)
C.spacing.plus:Click(); eq(db.spacing, 3)
local s0 = db.scale
C.scale.plus:Click(); check(math.abs(db.scale - (s0 + 0.05)) < 1e-6, "scale +0.05")
C.growUp:Click(); eq(db.growUp, true, "grow up")

section("look")
C.showBg:Click(); eq(db.showBg, false)
C.bgAlpha.minus:Click(); check(db.bgAlpha < 0.7, "bg alpha down")
C.showBorder:Click(); eq(db.showBorder, false)
C.redEdge:Click(); eq(db.redEdge, false)
eq(C.headerColor:GetText(), "Header colour: Gold")
C.headerColor:Click(); check(db.headerColor ~= "gold", "colour cycles")

section("grouping")
local g = C.group.FORTITUDE
check(g ~= nil, "group button per buff")
eq(g:GetText(), "Group")
g:Click(); eq(ns.ClassConfig("PRIEST").groups.FORTITUDE, "OPTIONAL")
g:Click(); eq(ns.ClassConfig("PRIEST").groups.FORTITUDE, "SELF")
g:Click(); eq(ns.ClassConfig("PRIEST").groups.FORTITUDE, "GROUP")
C.showWho:Click(); eq(db.showWho, false)

section("when to show")
C.showInCombat:Click(); eq(db.showInCombat, false)
C.onlyInGroup:Click(); eq(db.onlyInGroup, true)
eq(C.whenNone:GetText(), "Nothing missing: Hide")
C.whenNone:Click(); eq(db.whenNone, "fade"); eq(C.whenNone:GetText(), "Nothing missing: Fade")
C.lock:Click(); eq(db.locked, false, "unlock button")
C.lock:Click(); eq(db.locked, true)

section("combat")
db.onlyInGroup = false; db.showInCombat = true; refresh()
enterCombat()
C.layout:Click()
C.iconSize.plus:Click()
eq(errorsPrinted(), 0, "changing options in combat does not touch protected frames")
leaveCombat()
eq(errorsPrinted(), 0, "applied after combat")

section("slash commands")
db.showWho = true; party({ { "Ann" } }); refresh()
SlashCmdList.MISSINGBUFFWARNING("strip"); eq(db.layout, "strip")
SlashCmdList.MISSINGBUFFWARNING("panels"); eq(db.layout, "panels")
SlashCmdList.MISSINGBUFFWARNING("list"); eq(db.layout, "list")
SlashCmdList.MISSINGBUFFWARNING("debug")
check(db.lastDebug and #db.lastDebug > 3, "debug lines saved")
local joined = table.concat(db.lastDebug or {}, "\n")
check(joined:find("party FORTITUDE") ~= nil, "debug lists party state")
SlashCmdList.MISSINGBUFFWARNING("test"); FAKE.flushTimers()
SlashCmdList.MISSINGBUFFWARNING("reset"); eq(db.scale, 1, "reset scale")
SlashCmdList.MISSINGBUFFWARNING("unlock"); eq(db.locked, false)
SlashCmdList.MISSINGBUFFWARNING("lock"); eq(db.locked, true)
eq(errorsPrinted(), 0, "no errors from commands")
