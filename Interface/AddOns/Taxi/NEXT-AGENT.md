# Taxi - next agent (parked 2026-11-07)

**State:** Design approved by the owner (`DESIGN.md`, revamped: class + place search via /who, tick list, pasted message, Send whispers all ticked, paced ~1.5 s, sent marks). Plan in `PLAN.md`. Throwaway spike addon `..\TaxiSpike` built and loads against a fake API; NOT yet tested in the real game.

**Mockup update 2026-11-07:** owner sketch shows title TAXI, tabs Going | Stay | LFG, table Name | lvl | Where. LFG = find players to join your group. DESIGN.md updated; not yet re-approved.

**Waiting on owner:** full WoW client relaunch, then in game:
- `/txs api`
- `/txs who Warlock Orgrimmar`
- `/txs w <friend> test`
- `/txs chain <friend1,friend2> test`
and paste the printed output.

**Decision gate (PLAN.md Task 1 step 4):** if who and whispers (incl. chain) work, write detailed Phase 2 tasks and build Taxi. If blocked, stop and report what the game allowed; no fallback pre-approved.

**Other open items (not Taxi):** MissingBuffWarning - owner to confirm Touch of Weakness re-add works. Stutter - owner reseating 12V-2x6 cable; on another reset compare Kernel-Power 41 with `D:\GAMMA\stutter-handoff.md`.

## Spike results (2026-11-08)
- VERIFIED via TaxiSpikeDB probe: `C_FriendList.SendWho('c-"Warlock" z-"Orgrimmar"')` from an addon works: 1 WHO_LIST_UPDATE, 50 results (cap), GetWhoInfo(1) gave name/level/area. Build 16001.
- OBSERVED: five more who queries sent 6 s apart got no event and kept the old 50 results, so who is throttled beyond 6 s (interval unknown). An earlier manual `/txs who` once printed 0 results (cause unknown, maybe throttle or race).
- STILL UNTESTED: whispers from addon (`/txs w`, `/txs chain`), real throttle interval.
- SavedVariables only flush on /reload after a short delay (file appears ~seconds later).

## Build status (2026-11-08)
- BUILT: `Taxi.toc`, `Core.lua` (filter, who search, sent marks, paced sender), `UI.lua` (tabs Going/Stay/LFG, class cycle button, place box, tick list, message box, Send/Stop/Tick all/Tick none/Clear sent). `/taxi` toggles.
- VERIFIED (fake API, Lua 5.5 via lupa, `D:\GAMMA\taxi_build\test_core.py` and `test_ui.py`): core logic checks and a UI smoke run both pass.
- NOT VERIFIED in game: window look and layout, templates (UICheckButtonTemplate, InputBoxTemplate, UIPanelScrollFrameTemplate), timer-spaced whispers, who throttle interval, server "player not found" replies still mark the person as sent.
- Owner decision pending: re-approval of the design with tabs (owner said build now).
- Next: owner relaunches WoW (new addon folder), `/taxi`, tests; then visual mockup pass and cleanup (delete TaxiSpike when done).

## In-game results (2026-11-08, owner-reported)
- OBSERVED: window opens and looks right; Orgrimmar warlock search lists players; Send to ticked whispered ticked players and marked them "(sent)".
- Still unconfirmed: multi-player timed send (2+ ticked), Stay/LFG tabs, repeat-click skip, offline player still marked sent.
- Open: delete `..\TaxiSpike` when owner is done; owner mockup pass (colours/theme) not requested yet.

## Offline replies (2026-11-08, built, NOT confirmed in game)
- Core.lua listens to CHAT_MSG_SYSTEM; "No player named 'X' is currently playing." (ERR_CHAT_PLAYER_NOT_FOUND_S) within 30 s of a whisper un-marks X and flags offline; UI shows red "(offline)". Fake-API tests pass. Needs /reload then an in-game test with an offline name. Unknown: whether the game's reply text/event matches the global on Forever.

## Milestone (2026-11-08): Taxi v1 working in game (owner-confirmed)
- Features live: tabs Going/Stay/LFG; class button; place box; Level min/max (server filter + client-side safety filter, saved per tab); tick list; per-tab saved results; message box; Send to ticked (1.5 s paced), Stop, Tick all/none, Clear sent; LFG dungeon picker (20 Vanilla dungeons sorted by level fills level + message). `/taxi`.
- Tests: `D:\GAMMA\taxi_build\test_core.py`, `test_ui.py` (fake API, lupa Lua 5.5) pass.
- Open: delete `..\TaxiSpike` (owner has not said yes); dungeon level ranges are from memory; multi-person timed send and offline-player handling not explicitly confirmed; visual restyle to the owner's mockups not requested; who throttle interval unknown.
