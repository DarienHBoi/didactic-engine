# ZugDAQ (addon)

The in-game half of the ZugDAQ app, for WoW Forever (Interface 16001). It replaces **Gold Ledger** and
**Profession Guide**: everything both did is here, and it talks to the ZugDAQ app both ways.

- **Out to the app**: your gold, income and spending, auctions, farming runs, bags, banks and warbank (with a log of
  how each item's count changes), recipes and skill-up colours, vendors you've visited. The app reads the addon's
  saved data every time the game saves it (on /reload and logout).
- **In from the app**: the app writes `Data\FromApp.lua` whenever its data changes, and the game reads it at login
  and on /reload:
  - item tooltips show the app's market price, 7-day average, how many sell a day, and any deal or weekly price cycle;
  - what the app sends sits under the same tabs as in the app: deals from the latest AH snapshot under Auction House,
    what to sell under Inventory, the crafting plan open in the app and its shopping list under Crafting, and the
    guild board and guild trade matches under Guild;
  - when Auctionator has no price for an item, the app's price is used instead.

The window has the app's tabs: Overview, Profile, Auction House, Inventory, Crafting and Guild. Crafting includes the
old Profession Guide (Skill-ups and Recipes to get); it no longer opens its own window beside the game's.

The app installs this addon (the link in its status bar), and warns when its copy is newer than yours: click
**Update addon** there, then /reload. The addon warns too, in chat at login and at the top of its window. A first
install, or an update that adds files, needs WoW restarted rather than just /reload.

## Commands

    /zug (or /zugdaq, or the old /ledger)   open or close the window
    /zug farm start [route] | pause | resume | stop | cancel
    /zug watch <item> | unwatch <item>
    /zug value best|auction|vendor
    /zug deal <percent>
    /zug autoscan on | off | <minutes> | now   scan the AH by itself on opening it when prices are old (default: 60)
    /zug live | minimap
    /zug blocked        what the game last blocked the addon from doing (for bug reports)
    /pg                 Crafting > Skill-ups: cheapest skill-ups and recipes to get (was Profession Guide)

## Moving in from Gold Ledger and Profession Guide

The old `GoldLedger` and `ProfessionGuide` folders become small stubs. They load the old saved data before ZugDAQ,
which takes it over the first time it loads (per character for Profession Guide's recipe scans). Once each character
has logged in with ZugDAQ, the two stub folders can be deleted.

## Credits

Recipe source data (trainer, vendor, quest, drop; skill requirements; vendor locations) comes from
**What's Training?** by Sveng, Forever ("Camelot") edition, MIT licence: see `Data/Recipes/LICENSE-WhatsTraining.txt`.
Prices come from **Auctionator** when it's installed, and from the ZugDAQ app. Bundles LibStub, CallbackHandler-1.0,
LibDataBroker-1.1 and LibDBIcon-1.0 for the minimap button.
