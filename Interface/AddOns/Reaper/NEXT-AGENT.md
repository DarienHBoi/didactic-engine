# Reaper (a quiet Shadow Word: Death signal)
Design: docs/reaper-design.md (2026-11-21), REDESIGNED 0.2 the same day on owner direction: "I just want a notification when to use shadow word death, not big aggressive execute words, visual on flashing the spell or a way to display it above or in the nameplate like doesitdie does." Built test-first. 0.2 NOT yet seen in game.

## What it shows (0.2)
- SW:D spell icon (17 px, option 12-28) above the right end of the TARGET's plate bar (target frame when its plate is not drawn). Dim grey copy at the ready amount (kill + lead-time damage), coloured icon with an alpha pulse 0.6-1 over 1 s at the kill amount. Both are DoesItDie clip flags (secret-safe). No text, no centre alert, no skull, no glow flood, no sound.
- Optional thin kill tick (1 px) on every attackable plate.
- Optional soft glow over the SW:D action button(s): our own frame on UIParent, a clip flag at the ready amount. Buttons found out of combat by slot (Blizzard bar prefixes + EllesmereUI EABButton<slot>) via GetActionInfo or C_ActionBar.FindSpellActionButtons; buttons are only read. Never ActionButton_ShowOverlayGlow. No button: nothing, plate icon stays.
- Usable gate (L.usable): hidden on a plain "no" from C_Spell.IsSpellUsable (mana/known), C_Spell.GetSpellCooldown (own cooldown, GCD ignored) or C_Spell.IsSpellInRange per unit; secret/unknown keeps it.

## Perf (owner measured 1.253 ms/frame idle on 0.1)
- Event-driven: events wake a hidden driver frame; it draws once (0.1 s throttle) and hides. In combat a 0.5 s heartbeat (range, cooldown, rate decay). Plates tracked by NAME_PLATE_UNIT_ADDED/REMOVED (bar cached per unit). Estimate retry by C_Timer (5 s, max 12). Smoke test: zero client calls over 100 idle frames, driver hidden.

## Files
- Logic.lua: pure and tested. Class table, rank pick (highest known rank WITH an amount; Forever reports higher ranks known with empty descriptions), learner, rate, amounts, DoesItDie remaining, usable gate, sanitize (keys leadTime, plateIcon, buttonFlash, tick, iconSize, learned; 0.1 keys dropped).
- Widgets.lua: plate widget (tick, ready/kill icon flags), button glow.
- Main.lua: events, plates, target frame, buttons, test mode, NectarKit modules icon/flash/tick, slash.
- Options.lua: /reaper window (lead time, icon/flash/tick checks, icon size, test, status).
- Slash: /reaper, /reaper icon on|off|<px>, /reaper flash on|off, /reaper tick on|off, /reaper test, /reaper status.
- Tests: `python reaper_tests/run.py` (logic, smoke with fake Forever incl. idle call count, estimate, options, queue). Keep `python nectarkit_tests/run.py` green.

## Check in game first
1. /reaper status: "rank N; estimate NNN" (or learned), "button flash N button(s) found".
2. /reaper test on a target out of combat: pulsing SW:D icon above the target's bar.
3. /nk perf idle: Reaper under 0.05 ms/frame.
4. Real fight: grey icon near the end, coloured pulse when it kills; hidden out of range / no mana / on cooldown.
5. Button glow on the SW:D button when the target is in range; if "0 button(s)", the bar addon's button names are not covered (HUI?).
6. Clip technique on frames as DoesItDie does (texture on the long bar inside the clipping window); confirm icon is hidden above kill range.

## History
- 2026-11-21 0.3 (owner: brighter, time SW:D with DoesItDie's DoT projection). Kill = SW:D + DoT damage due within the reaction time (leadTime, default 0.6 s); soon (grey icon, alpha 0.7) = SW:D + max(DoT due in 2 s, damage rate x 2); finish = DoT due in 1.5 s. DoT due = DoesItDie.GetDoTs remaining damage spread evenly to expiresAt (its API has no tick times; inferred close enough). Kill icon: pulse 0.8-1 plus a violet ADD glow ring. Both icons (and the button glow) sit in a "gate": a clip frame over the UNFILLED part of a bar (max = health, value = finish), so they vanish when your DoTs finish it; a 5 px grey dot (flag at finish) shows instead. No DoesItDie: dots nil, current health only. Tests 402/0. Backup Desktop Reaper-backup-2026-11-21d (0.2). NOT yet seen in game: confirm nested clipping (gate > flag window) hides/shows as designed.
- 2026-11-21 FIX (owner report "nothing draws", status "rank N; no amount known yet", seen in game): the client calls a higher SW:D rank known while its description is EMPTY. pickSpell now takes the highest known rank with an amount; C_Spell.RequestLoadSpellData + SPELL_DATA_LOAD_RESULT re-pick. Backup Desktop Reaper-backup-2026-11-21b.
- 2026-11-21 0.2 redesign + perf (above). Backup Desktop Reaper-backup-2026-11-21c (the fix build).

## Known limits
- Rate counts all damage including DoT ticks, which DoesItDie remaining damage also counts: ready is a little early (safe side).
- Icon only on the target's plate (you can only cast at the target); other plates get the tick.
- Percent classes (Warrior Execute 20%) listed but inactive.
