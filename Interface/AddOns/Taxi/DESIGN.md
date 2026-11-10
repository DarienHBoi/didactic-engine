# Taxi - design, revamped (2026-11-07)

A World of Warcraft addon for the **WoW: Forever** client (Interface 16001, modern addon API, Lua 5.1).
Install folder: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Taxi`.
This revamp replaces the first design (two tabs "Going"/"Staying", warlock-only, one click per whisper). The owner changed direction after the first draft was reviewed.

## Intent and why
The owner (a Priest on Forever) wants to find players of a chosen class in a chosen place and message them quickly, for example warlocks who could summon them. Typing the same whisper to many people by hand is slow. Taxi lets them pick a class and a place, see who is there, tick the people to contact, paste one message, and send it to all ticked people with one click.

## What it does (decided by the owner)
1. **Choose a class** to look for (not only warlocks).
2. **Choose where to search** (a place the owner types or picks).
3. A **list of matching players** is shown. A **tick box** on each row marks who to whisper. A person already whispered is marked so they are not contacted twice.
4. A **message field** where the owner pastes what they want to say.
5. A **Send button**: one click whispers **everyone ticked**, with the message from the field.
6. A neat window at the side of the screen (the owner will supply visual mockups; follow them where they differ).

## Owner mockup (2026-11-07, hand sketch, supersedes my earlier "no tabs" call)
Title "TAXI". Three tabs under it: **Going | Stay | LFG**. Below, a table with columns **Name | lvl | Where** and rows of players. The controls from the revamp (class picker, place box, message field, Send) are not drawn; builder places them under/around the table. The LFG tab (owner decided): find players to join your group; same list and whisper tools, any class and place, with its own group-invite message.

## My calls (the owner has not decided these - treat as my calls, they can overrule)
- **Three tabs per the mockup: Going, Stay, LFG.** Each tab keeps its own message text and its own sent marks. Going = you want to travel to X; Stay = you want a friend pulled to you (see the first design intent). LFG = find players to join your group.
- **Two marks per row:** a *tick box* = "send to this person" (set by the owner), and a *sent mark with time* set automatically after a whisper. After sending, the row's tick is cleared and a sent mark is shown. A person who already has a sent mark is skipped by Send until the wait expires, even if ticked (anti-repeat).
- **Pause between whispers:** Send does not fire all whispers in the same instant. It sends one every ~1.5 seconds (builder may tune), shows progress ("Sending 3/12..."), and a Stop/Cancel button. This protects against game throttling and looking like spam.
- **Persistence:** sent marks (name + time) are saved so a relog or `/reload` does not let the owner re-whisper someone immediately. Marks expire after a wait (builder picks, e.g. 5 minutes for repeated requests; the owner can clear them with a button).
- **Results:** sorted by level (highest first). No other filtering in v1. A level-20+ filter applies only when the class is Warlock (summoning level - inferred from the classic game, verify).
- **Message:** the field's text is saved between sessions. The message is sent exactly as pasted. No placeholders in v1.
- **If a whisper cannot be sent** (client blocks it): say so in the window; fall back to prefilling the chat box with `/w name text` for the owner to press Enter, one person at a time.

## Goals
- Fast and neat: class, place, tick, paste, send.
- Looks like a proper WoW window (dark brown, bronze border, gold titles, white text; `BasicFrameTemplateWithInset` is known to be available in this client; matches the owner's MissingBuffWarning addon).
- Never silent: if a search or whisper cannot run, the window says why.

## Non-goals
- No automatic whispering: nothing is sent unless the owner clicks Send.
- No finding helpers for the three-person summon ritual, no travel features, no summon logic of any kind.
- No whisper replies handling in v1 (no reading answers back).

## Anti-goals (a failure even if it technically works)
- Whispering the same person repeatedly by accident.
- A Send that floods in one instant and gets the owner throttled or reported.
- A cluttered window that does not match the WoW look.

## Constraints and unknowns (must be verified, not assumed)
- **Finding players (biggest risk).** Plan: a `/who` search (class + zone) via the game's who/friend-list API, results arriving by event. **No addon in the owner's AddOns folder uses it, so it is unverified that Forever lets addons run `/who`**, whether it needs a click, and how it throttles (about 50 results classically; the zone filter matches zone names, not subzones).
- **Decided by the owner: test `/who` first.** Step 1 is a throwaway spike: a tiny test addon that tries a class + zone `/who` search from an addon in the real game and reports what happened. The owner runs it in game. **If it works, build Taxi. If it is blocked, stop and come back to the owner with what the game allowed; no fallback version is pre-approved.**
- **Whispers.** Other addons here send chat through `C_ChatInfo.SendChatMessage`. It is unverified whether sending a whisper from an addon is restricted, or whether several whispers from one click (spaced by a timer) each need their own click (hardware event). The builder must test this in the spike too.
- **Place text -> zone.** Free text from the owner; builder decides matching (zone name list with fuzzy matching, or pass-through). Subzones and instances are out of scope.
- **Testing.** Outside the game only a fake-API Lua harness can run (the owner's earlier addon used a lupa Lua 5.1 harness). Real behaviour needs the owner to test in game. No "works" claim without that.

## Left to the builder
File layout, saved-variable names, slash command (suggest `/taxi`), visual layout (follow the owner's mockups), the zone-matching approach, exact pause and expiry times, and how the class picker and place box look.
