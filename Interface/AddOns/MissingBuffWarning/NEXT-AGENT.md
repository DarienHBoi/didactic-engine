# MissingBuffWarning - state (2026-11-07)

WoW Forever addon (Interface 16001, Lua 5.1). Flashes big icon + "NO <BUFF>" mid-screen when a tracked buff is missing, out of combat only.

## Done / verified
- Files: MissingBuffWarning.toc, Core.lua (logic + warning frame + events + /mbw), Options.lua (panel + Settings category).
- 52/52 checks pass against a fake WoW API (harness in the Claude session scratchpad, throwaway; lupa Lua 5.1). Not a real-game test.
- Verified in game by owner: addon appears in Options > AddOns after a full client relaunch (/reload does NOT discover new addons).
- Priest built-ins: Inner Fire, Power Word: Fortitude (on); Divine Spirit, Shadow Protection, Shadowform (off). Group versions (Prayer of ...) count. Unlearned spells are skipped. Manual buffs by name or ID, de-duplicated.
- Commands: /mbw (panel), /mbw unlock|lock|reset|debug. Handle bottom-left scales live, top-right corner pinned.

## Restyle (2026-11-07, owner asked "WoW theme")
- Settings window: BasicFrameTemplateWithInset (verified used by 17 installed addons), plain-box fallback, gold header dividers.
- Warning: gold-bordered icon + red glow (atlas ParagonReputation_Glow) + banner plate "MISSING" / buff name. 54/54 fake-API checks pass; look NOT seen in game yet.

## Owner confirmed in game (2026-11-07)
- After restyle the warning was not visible; after /reload + /mbw reset + /mbw test it shows. Likely cause (inferred, not proven): saved position x=1812,y=1137 was off-screen. Fixed: off-screen saved positions are discarded in ApplyPosition.
- Added: /mbw test (8 s sample), errors printed once to chat (ns.Refresh pcall wrapper). 61/61 fake-API checks pass.
- Still to confirm with a real missing buff: drop Inner Fire out of combat, flash should appear within ~1 s; /mbw debug output not yet seen.

## Always-on change (2026-11-07, owner request)
- Owner: warning showed intermittently; wants it ALWAYS until the buff is on. Now shown in combat too (earlier "out of combat only" rule dropped); 1 s safety-net ticker; pulse fades only to 60% alpha; if aura names are secret (combat limits) the display is left unchanged. Dead/ghost/taxi still quiet. 65/65 fake-API checks pass; not yet confirmed in game.

- CONFIRMED by owner in game: warning is steady (always on while a buff is missing). Milestone closed 2026-11-07. Open: not yet checked in combat with names hidden; no sound; Priest only.

## Panel look + combat (2026-11-07, later)
- Owner sent a reference image (WoW trainer/info panel: dark brown, bronze border, gold title, white text, faint watermark). Warning is now that panel per missing buff: gold title = buff name, white body "Your X is missing. Cast it to dismiss this warning.", desaturated icon watermark bottom-right. 65/65 fake-API checks pass; not seen in game.
- Owner reports the warning still does not show IN COMBAT. Unknown cause. Suspect the game hides player aura names in combat (code then leaves the display unchanged). /mbw debug now prints inCombat, auras read, names hidden. NEXT: owner runs /mbw debug during combat; if "names hidden" > 0 find a combat-safe check (e.g. C_UnitAuras.GetPlayerAuraBySpellID) - do not guess.

- Diagnostics: Refresh writes MissingBuffWarningDB.diag.inCombat / .outOfCombat {aurasRead, namesHidden, namesVisible, missingNow, time}. Owner fights with a buff off, then /reload; read WTF/Account/*/SavedVariables/MissingBuffWarning.lua (agent can read it directly). Decide the combat fix from namesHidden/aurasRead.

- Owner asked for colour + icon size: watermark replaced by a full-colour 72px icon in a bronze frame on the left of a 300x110 panel (ICON/SLOT/PANEL_H constants at top of the warning-frame section in Core.lua). Interpretation is mine; unconfirmed in game.

- CONFIRMED by owner: the coloured 72px icon panel "looks right" (2026-11-07). Remaining open item: warning in combat (needs the fight test + diag read).

- CONFIRMED by owner: warning shows in combat (2026-11-07). Diag showed combat read 4 auras, 0 hidden, so Forever did not hide names; earlier "not showing in combat" was most likely the old out-of-combat-only build. Temporary diag recording removed (db.diag cleared). /mbw debug still prints inCombat/auras read/hidden.
- Milestone closed: Priest addon done and owner-confirmed. Open ideas only: sound alert, more classes, party/raid checks.

## DONE, awaiting in-game check: shift-click spell into the Add box (2026-11-07)
- Options.lua onInsertLink hooks ChatFrameUtil.InsertLink and ChatEdit_InsertLink (pattern copied from Auctionator/AceGUI in this folder). If the Add box has focus and the link is a spell link, it fills the box with the spell name and calls addManual() at once (auto-add is my call; easy to change to fill-only). 0.2 s guard against double-fire; item links ignored. 71/71 fake-API checks pass. NOT yet verified against the real spellbook (owner to test: click the Add box, shift-click a spell).
- Owner reported "nothing happens" in game. Added /mbw linkdebug (prints every link passed to the insert hooks + whether Add box has focus + which hooks installed); hooks now install independently. NEXT: owner runs /mbw linkdebug, clicks the Add box, shift-clicks a spell; read the chat lines. If NO line appears, the spellbook does not call these functions: grep/hook the spellbook button click instead (PlayerSpellsFrame / SpellBookFrame / SpellButton modified click). If a line appears with addBoxFocus=false, the click stole focus. 75/75 fake-API checks pass.
- Owner: linkdebug showed nothing after shift-click => spellbook does NOT call ChatEdit_InsertLink/ChatFrameUtil.InsertLink (inferred from "nothing there"; the ON line itself was not pasted).
- Owner screenshot (2026-11-07): spellbook is the OLD-STYLE parchment "Spellbook" (classic SpellBookFrame/SpellButton, rank text, Page 1/1), not PlayerSpellsFrame. Chat also showed "...action failed because of an AddOn" (taint; addon not identified, could be unrelated to MBW).
- Added /mbw probe: records the next 8 clicks (frame chain, fields, tooltip spell) into MissingBuffWarningDB.probe (read WTF/Account/*/SavedVariables/MissingBuffWarning.lua after /reload). 80/80 fake-API checks pass. NEXT: owner runs /mbw probe, clicks Add box, shift-clicks a spell, /reload; read ns.db.probe, then hook the real spell button click (likely SpellButton_OnModifiedClick / SpellButton_OnClick via hooksecurefunc, spell id via SpellBook_GetSpellBookSlot + GetSpellLink / C_SpellBook). Ask owner when the "action failed" message appears (on shift-click?) before blaming MBW.
- CONFIRMED by owner: shift-click from the old-style spellbook adds the spell (2026-11-07). Temporary /mbw probe removed; /mbw linkdebug kept.
- Owner request: click the warning panel to cast the spell. Built (not yet confirmed in game): per-buff panels keyed by label; each castable panel gets a SecureActionButtonTemplate child (type=spell, spell=<label>, unit=player), created ONLY out of combat (attachCast in Core.lua); panels show/hide in combat without touching the secure buttons; unlocked mode makes the button ignore the mouse so the panel can be dragged. 88/88 fake-API checks (the fake game raises an error if a secure frame is touched in combat). Risks to check in game: click casts on self; works in combat; "action failed because of an AddOn" message must NOT appear from this; Fortitude/Inner Fire cast by name picks highest rank.
- Owner: click-to-cast "nop" (does not cast). Suspected cause (inferred, unconfirmed): button registered only AnyUp while the game's ActionButtonUseKeyDown cvar may make secure buttons fire on key-down. Now RegisterForClicks("AnyUp","AnyDown"); /mbw debug prints castOnKeyPress cvar, createError, and per panel: shown / button exists / spell attr / mouse enabled. 90/90 fake-API checks. NEXT: owner /reload, take a buff off, click panel; if still no cast, owner sends /mbw debug lines. Other suspects: another frame above the panel eating clicks, spell attribute name, button not created (createError).
- CONFIRMED by owner: click-to-cast works after registering both click phases (2026-11-07). Not yet checked: casting in combat, and whether an "action failed because of an AddOn" message ever appears from MBW.
- Milestone closed. Open ideas only: sound alert, more classes, party/raid checks. Next agent: start from this file; test harness must be recreated (lupa Lua 5.1 + fake WoW API, 90 checks).
- Owner report (2026-11-07): "Touch of Weakness isn't working". Screenshots showed the manual list held "Touch of the Grave (Racial Passive)" (a different spell, "?" icon) and the real Touch of Weakness buff was up. Cause: names with subtext "(Racial Passive)"/"(Rank 1)" never matched buff names; shift-click copied the link text. Fixed: shift-click uses the spell's resolved name (fallback: link name with subtext stripped); BuildTracked retries with subtext stripped and also accepts the plain name as an aura alias. 95/95 fake-API checks. Owner must remove the old entry and re-add Touch of Weakness; unconfirmed in game. Open question: why the shift-click produced Touch of the Grave instead of Touch of Weakness (owner may have clicked the racial passive).
- Owner: Touch of Weakness panel "still not casting" (2026-11-07; Fortitude/Inner Fire click-cast OK). /mbw debug now also saves its lines to MissingBuffWarningDB.lastDebug (read WTF/Account/*/SavedVariables/MissingBuffWarning.lua after /reload) and lists each tracked buff with castable + aura names. NEXT: owner takes Touch of Weakness off (panel visible), runs /mbw debug, /reload; read lastDebug: check castable, button=true, spell attr, mouse, createError. Suspects: castable=false (spell name not resolved => no button), racial spell name differs from aura name, button created before label fix.
- Owner kept clicking the panel for "Touch of the Grave" (Forsaken racial PASSIVE, General tab), not Touch of Weakness (Shadow Magic tab). Passives cannot be cast. Now: ns.IsPassive (C_Spell.IsSpellPassive / IsPassiveSpell, pcall) => entry.passive, castable=false, no secure button, body text "It is a passive effect: it cannot be cast." 100/100 fake-API checks. Owner still has to remove the Touch of the Grave entry and add Touch of Weakness from the Shadow Magic tab; unconfirmed in game.
- Owner: "not being warned of any buff atm" (screenshot in Orgrimmar, 3 buffs up, appears to be on a flight-path wyvern). By design warnings pause on a flight path (UnitOnTaxi) and when dead/ghost. /mbw debug now also prints state: onTaxi, deadOrGhost, locked, panelsShown (saved in db.lastDebug). 103/103 fake-API checks. Unconfirmed whether the owner was on a taxi; if not, read lastDebug (tracked list, buffs list, state).
- Original request text kept below for reference.

## (old) request 2026-11-07
"Shift-click a spell in the spellbook into the Add box of the 'Your own buffs' section, like shift-clicking links into chat."
- Where: Options.lua, panel.edit (EditBox, InputBoxTemplate) + addManual().
- Approach (to verify, not guess): when panel.edit has focus, a shift-clicked spell link must go into it. Spellbook shift-click calls the chat link insert function (ChatEdit_InsertLink in older API, ChatFrameUtil.InsertLink in newer). First grep the other installed addons in this AddOns folder for ChatEdit_InsertLink / ChatFrameUtil.InsertLink / HandleModifiedItemClick to see what Forever actually uses; hooksecurefunc it, and if panel.edit:HasFocus() then panel.edit:Insert(link) and return. Also consider a second hook on the spellbook button click if the insert function does not fire with no chat box open.
- Link format: |cff71d5ff|Hspell:ID:...|h[Name]|h|r. Parse spellID/name from the link (string.match "|Hspell:(%d+)" and "%[(.-)%]"), put the NAME (or id) in the box, then addManual() (already handles names and IDs, de-duplicates).
- Test: extend the fake-API harness (scratchpad is gone with the session; recreate: Python venv + lupa lua51, mock WoW API, ~65 checks) with a test that simulates the hook with a spell link. Real-game check by owner.
- Rules: do not widen scope; owner confirms in game. Keep tests green (65/65 baseline).

## NOT verified in the real game
- Icon fallback paths, spell lookup by name, handle graphic, exact panel look, flash visibility.
- First in-game step: /mbw debug and send output; /mbw unlock to check move/resize.

## Ideas not built
- Sound alert, other classes (data table ns.BUILTIN in Core.lua), party/raid checks.

## Rules
- Out-of-combat only (Midnight-style combat-data limits assumed from fan guides, unofficial).
- Do not widen scope without owner yes.

## 2026-11-07 owner confirmation
- Owner confirmed click-cast works in game ("its working fine"); the earlier Touch of the Grave report was owner error. No open issues. Open ideas only: skip-passives option, sound alert, more classes.

## 2026-11-08 shift-move
- Live warnings: shift-drag moves, shift+mouse wheel scales (0.05 steps), holding shift shows the bottom-left resize handle. Not in combat (box holds secure click-cast buttons, so the game would block it). Options rows restyled (dark bordered rows, gold names, footer). Not yet confirmed in game.

## 2026-11-15: compact grouped display BUILT (v0.2.0) - NOT yet seen in game
Design: MBW-compact-design.md (this folder). Backup of v0.1 before the change: Desktop\MissingBuffWarning-backup-2026-11-15.
- Files: Core.lua (data, settings + migration, logic, party scan, refresh, events, /mbw), Display.lua (NEW: box, 3 layouts, click-to-cast, combat rules), Options.lua (two columns: buff list with Self/Group/Optional button per buff; right column = layout, size/spacing, look, grouping, when to show), MinimapButton.lua unchanged.
- Layouts (db.layout): "list" (A, default) header "Missing buffs (N)", collapsible Self/Group/Optional, 16px icons with red edge, "have/total" and nested names of party members missing a group buff (each name line casts on that member); "strip" (B) icons (iconSize+8), gold divider between groups, badge = number of others missing it, tooltip = name + who, Optional dimmed; "panels" = old big panels. Also /mbw list|strip|panels.
- Settings (MissingBuffWarningDB, version=2): layout, scale, x/y, locked, iconSize, spacing, fontSize, growUp, showBg, bgAlpha, showBorder, headerColor (gold/white/blue/green), redEdge, showWho, showInCombat, onlyInGroup, whenNone (hide/fade), collapsed{ALL,SELF,GROUP,OPTIONAL}; per class classes.X.groups[key] (key = builtin key or "M:<lower name>"). Migration keeps scale/position/lock/enabled buffs/manual/minimap, drops old probe/diag junk. x/y = top-right corner (bottom-right when growUp).
- Party check: party/raid members' auras read OUT OF COMBAT ONLY (1 s ticker + GROUP_ROSTER_UPDATE); dead/offline skipped; hidden (secret) names or a throwing aura read keep the member's last known state; in combat the group info stays as last known.
- Combat rule (inferred from how WoW protects secure frames, not proven in Forever): layout happens only out of combat and once more on PLAYER_REGEN_DISABLED (just before lockdown). In combat nothing that holds a cast button is shown/hidden/moved; a buff that comes up is dimmed (alpha 0.3), a buff lost mid-fight that has no line is named in a red footer "Also missing: X". "Nothing missing: hide" keeps the (empty) box shown so that footer can still appear in combat. Collapse/options changes in combat wait until combat ends.
- Click-to-cast unchanged in principle: SecureActionButtonTemplate per line/icon/panel, type=spell, spell=label, unit=player (group buff you already have: first party member missing it), Up+Down clicks, mouse off while unlocked. Shift-drag moves, shift-wheel scales, bottom-left handle scales.
- Tests: tests/ in this folder (WoW ignores it): python tests/run.py -> 203/203 pass (lupa Lua 5.1 fake client; fake raises an error if a protected frame is shown/hidden/moved/re-attributed in combat). Mutation check: forcing full layout in combat makes 12 checks fail, so the combat checks bite. Salesman suite (other project) 1088/1088 unaffected.
- NOT verified in game: look of list/strip, font/size defaults, tooltip, footer, party names, casting on a party member, whether Forever really blocks hiding a frame with a secure child (if it doesn't, the in-combat rule is just extra caution).
- NEXT: owner /reload, checks list (default), /mbw strip, /mbw panels, options panel; then a fight with a buff off; in a party check the names and click-to-cast on a member. Report problems with /mbw debug (saved to db.lastDebug).
