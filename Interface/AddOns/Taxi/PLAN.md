# Taxi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development) task-by-task. Steps use checkbox syntax.

**Goal:** A side window to pick a class and place, list matching players from `/who`, tick them, paste one message, and whisper all ticked with one click (paced).

**Architecture:** Phase 1 is a throwaway spike addon (`TaxiSpike`) that proves, in the real game, that an addon can (a) run a class+zone `/who` and read results, (b) send whispers, including several from one click spaced by a timer. Phase 2 (real `Taxi`) is only started if the spike passes.

**Tech Stack:** WoW Lua 5.1, Interface 16001, `BasicFrameTemplateWithInset`, SavedVariables `TaxiDB`.

**Spec:** `AddOns\Taxi\DESIGN.md`

## Global Constraints
- Install under `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`.
- Nothing is sent unless the owner clicks Send (or types a spike command). No auto whispering.
- Spaced whispers: about 1.5 s apart, with progress and a Stop button.
- Sent marks persist across `/reload`; owner can clear them.
- A new addon folder needs a full client relaunch; `/reload` is enough for edits.
- No "works" claim without in-game confirmation from the owner.

## Review Focus
- `/who` returns nothing or is throttled: window must say so, not sit silent.
- More results than the list cap (~50): show a "list truncated" note.
- Ticked person already marked sent: skipped, not re-whispered.
- Send clicked with empty message or nothing ticked: refuse with a message.
- Whisper target went offline/renamed: report failure, continue with the rest.

---

## Phase 1: Spike (throwaway)

### Task 1: TaxiSpike addon

**Files:** Create `AddOns\TaxiSpike\TaxiSpike.toc`, `AddOns\TaxiSpike\TaxiSpike.lua`.

**Interfaces — Produces:** slash command `/txs` with subcommands:
- `/txs api` prints which of `C_FriendList.SendWho`, `C_FriendList.GetNumWhoResults`, `C_FriendList.GetWhoInfo`, `C_ChatInfo.SendChatMessage`, `SendChatMessage` exist.
- `/txs who <Class> <Zone...>` sends who filter `c-"<Class>" z-"<Zone>"`, waits for `WHO_LIST_UPDATE`, prints count and up to 10 `name level zone`; prints "no event after 5s" if none arrives.
- `/txs w <name> <text>` sends one whisper.
- `/txs chain <name1,name2,...> <text>` sends whispers 1.5 s apart from a timer started by that one command, printing each result.

- [ ] Step 1: write the `.toc` (`## Interface: 16001`, `## Title: Taxi Spike`) and Lua file; every API call wrapped in `pcall`, errors printed.
- [ ] Step 2: syntax-check the Lua (Lua 5.1 load, fake-API stub) — expect clean load and `/txs api` output.
- [ ] Step 3: owner relaunches the client, runs `/txs api`, `/txs who Warlock Orgrimmar`, `/txs w <friend> test`, then `/txs chain <two friends> test`; pastes the printed output back.
- [ ] Step 4 (decision gate): if who and whispers (incl. chain) work, go to Phase 2. If anything is blocked, stop and report exactly what the game allowed; no fallback pre-approved.

## Phase 2: Real Taxi (outline only; detail written after the spike result)
- Task 2: core module — who query, result cache, sorting, truncation note, sent-marks store with expiry (tested with the fake API).
- Task 3: sender — paced queue, skip rules, Stop, failure handling (tested with the fake API).
- Task 4: UI — class picker, place box, list with ticks/sent marks, message box, Send/Stop, `/taxi`, WoW styling per owner mockups.
- Task 5: in-game acceptance run by the owner.
