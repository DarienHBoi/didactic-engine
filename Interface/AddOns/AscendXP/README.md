# AscendXP v1.2.7 - Loot tracking reliability update

**For WoW Forever, interface 16001.**

This release preserves the existing bar and panel designs, rested XP display, quest projections, XP tracking, gold tracker, ledger, and Auctionator pricing.

### Fixed in v1.2.7

- Ordinary mob loot, gathered items and fish now use loot-window + confirmed bag changes as a fallback when a loot chat message is absent or unrecognized.
- Prevents double counting when bag updates happen before or after loot chat.
- Supports consecutive auto-loot windows and late inventory updates.
- Vendor purchases, auction transactions, customer-supplied trade materials, and crafting outside a loot window are not valued as farm drops.
- Newly received item-data notifications trigger price recalculation.
- Gold/hour responds when first tracked value arrives; early rates are preliminary until enough elapsed time has accumulated.
- Added `/axp golddebug` to show loot-window activity, parsed chat messages, bag checks, recorded pickups, and unpriced items. This prints locally to chat and does not send data anywhere.

**Note:** Gold/hour combines collected coin and estimated loot value, less tracked spending. Item prices are estimates, not realized auction sales. Items without known selling values remain at zero until priced. No existing saved settings or session ledger is reset during the upgrade.

### Installation

1. Exit the game.
2. Replace the entire `AscendXP` folder under your Forever client's `Interface/AddOns/` directory with the one from this ZIP.
3. Restart the client. You do not need to remove SavedVariables.

### Commands

- `/axp` opens settings. `/axp bar`, `/axp panel`, `/axp both` select layout.
- `/axp ledger` opens the pickup ledger. Right-click Gold/Hour for it, too.
- `/axp loot` opens the gold breakdown. `/axp gold` toggles gold stats.
- `/axp golddebug` shows loot-capture diagnostics in chat.
- `/axp reset` resets the XP and gold session (without changing your character's XP or wallet).

### Verification

Lua syntax checking and a simulated WoW-client test harness cover ordinary bag-only loot, chat-first and bag-first order, late chat, rapid consecutive loot windows, merchant purchases, trade materials, per-item prices, ledger totals, and a nonzero gold/hour after loot. Live testing on WoW Forever is still necessary.

**Created by Darktotem Inevitable.**
